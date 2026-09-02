#!/usr/bin/env python3
"""Validate PASSAGETR's bundled public content and its source-quality contracts."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

import build_static_content as builder


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DATA = ROOT / 'source_data'
EXPECTED = {
    'words': 5314,
    'readings': 678,
    'dictionaryEntries': 121772,
    'dictionaryHeadwords': 121501,
}
CURATED_SOURCE_NUMBERS = frozenset(range(1, 101))
CURATED_SENTENCE_COUNT = 15
CURATED_QUESTION_COUNT = 5


def load(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(value, dict):
        raise ValueError(f'Expected JSON object: {path}')
    return value


def normalized_dictionary_key(value: object) -> str:
    return builder.normalize_dictionary_key(str(value or ''))


def validate_pre_curated_generated_questions_backup() -> int:
    payload = load(
        SOURCE_DATA / 'legacy' / 'pre_curated_generated_questions_backup_v1.json'
    )
    readings = payload.get('readings')
    if not isinstance(readings, list) or len(readings) != 100:
        raise ValueError('Pre-curated generated-question backup must contain 100 readings.')
    questions = sum(
        len(record.get('questions', []))
        for record in readings
        if isinstance(record, dict) and isinstance(record.get('questions'), list)
    )
    if payload.get('questionCount') != questions:
        raise ValueError('Pre-curated generated-question backup count is invalid.')
    if {record.get('sourceNumber') for record in readings if isinstance(record, dict)} != CURATED_SOURCE_NUMBERS:
        raise ValueError('Pre-curated generated-question backup source-number coverage is invalid.')
    return questions


def load_curated_package() -> dict[int, dict[str, Any]]:
    path = SOURCE_DATA / builder.DEFAULT_CURATED_READINGS_RELATIVE_PATH
    records = json.loads(path.read_text(encoding='utf-8'))
    if isinstance(records, dict):
        records = records.get('readings', records)
    if not isinstance(records, list) or len(records) != 100:
        raise ValueError('Curated package must contain 100 readings.')
    by_source_number: dict[int, dict[str, Any]] = {}
    for record in records:
        if not isinstance(record, dict):
            raise ValueError('Curated package record is invalid.')
        source_number = record.get('source_number')
        if not isinstance(source_number, int) or source_number in by_source_number:
            raise ValueError('Curated package source numbers are invalid.')
        by_source_number[source_number] = record
    if set(by_source_number) != CURATED_SOURCE_NUMBERS:
        raise ValueError('Curated package source-number coverage is invalid.')
    return by_source_number


def curated_question(question: dict[str, Any], order: int) -> dict[str, Any]:
    return {
        'id': question['id'],
        'sortOrder': order,
        'type': question['type'],
        'questionCategory': 'comprehension',
        'question': question['question_en'],
        'questionTr': question['question_tr'],
        'options': question['options_en'],
        'optionsTr': question['options_tr'],
        'correctOptionIndex': question['correct_option_index'],
        'answerEn': question['answer_en'],
        'answerTr': question['answer_tr'],
        'explanation': question['explanation_en'],
        'explanationTr': question['explanation_tr'],
        'evidenceSentenceIndexes': question['evidence_sentence_indexes'],
    }


def canonical_passages() -> dict[str, dict[str, Any]]:
    passages: dict[str, dict[str, Any]] = {}
    for row in builder.read_csv(
        SOURCE_DATA / 'canonical' / 'readings' / 'reading_passages.csv'
    ):
        title = builder.clean(row.get('title'))
        source_pack = builder.clean(row.get('pack_name'))
        if not title or not source_pack:
            continue
        key = builder.normalized(title)
        if key in passages:
            raise ValueError(f'Duplicate canonical passage title: {title!r}')
        passages[key] = {
            'id': builder.passage_id(title),
            'title': title,
            'level': builder.nullable(row.get('level')),
            'category': builder.nullable(row.get('Category')),
            'sentences': [],
        }
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in builder.read_csv(
        SOURCE_DATA / 'canonical' / 'readings' / 'reading_sentences.csv'
    ):
        title = builder.clean(row.get('passage_title'))
        english = builder.clean(row.get('sentence_en'))
        raw_index = builder.clean(row.get('idx'))
        if not any((title, english, raw_index, builder.clean(row.get('sentence_tr')))):
            continue
        if not title or not english or not raw_index:
            continue
        try:
            index = int(raw_index)
        except ValueError as error:
            raise ValueError(f'Invalid canonical sentence index: {raw_index!r}') from error
        grouped[builder.normalized(title)].append({
            'index': index,
            'englishText': english,
            'turkishText': builder.nullable(row.get('sentence_tr')),
        })
    for key, sentences in grouped.items():
        passage = passages.get(key)
        if passage is None:
            raise ValueError(f'Canonical sentence has no passage: {key!r}')
        indexes = [sentence['index'] for sentence in sentences]
        if any(index <= 0 for index in indexes) or len(indexes) != len(set(indexes)):
            for index, sentence in enumerate(sentences, start=1):
                sentence['index'] = index
        else:
            sentences.sort(key=lambda item: item['index'])
        passage['sentences'] = sentences
    if len(passages) != 678:
        raise ValueError('Canonical passage coverage is invalid.')
    return passages


def validate_canonical_source_baseline() -> dict[str, Any]:
    expected = builder.canonical_source_baseline_payload(canonical_passages())
    actual = load(SOURCE_DATA / builder.SOURCE_BASELINE_RELATIVE_PATH)
    for field, value in expected.items():
        if actual.get(field) != value:
            raise ValueError(f'Canonical source baseline mismatch for {field}.')
    return expected


def validate_source_checksums(manifest: dict[str, Any]) -> None:
    checksums = manifest.get('sourceChecksums')
    if not isinstance(checksums, dict):
        raise ValueError('Source checksums are missing.')
    expected_paths = {
        'words': SOURCE_DATA / 'canonical' / 'words' / 'yds_words_set_001.csv',
        'passages': SOURCE_DATA / 'canonical' / 'readings' / 'reading_passages.csv',
        'sentences': SOURCE_DATA / 'canonical' / 'readings' / 'reading_sentences.csv',
        'dictionary': SOURCE_DATA / 'canonical' / 'dictionary' / 'dictionary_tr_en.xlsx',
        'curatedReadings': SOURCE_DATA / builder.DEFAULT_CURATED_READINGS_RELATIVE_PATH,
        'preCuratedGeneratedQuestionsBackup': (
            SOURCE_DATA / 'legacy' / 'pre_curated_generated_questions_backup_v1.json'
        ),
        'translationRepairs': (
            SOURCE_DATA / 'quality' / 'reading_translation_repairs_v1.json'
        ),
        'canonicalLanguageCorrections': (
            SOURCE_DATA / 'quality' / builder.CANONICAL_LANGUAGE_CORRECTIONS_FILENAME
        ),
        'contentRepairs': SOURCE_DATA / 'quality' / 'reading_content_repairs_v2.json',
        'contentRepairs101To300': (
            SOURCE_DATA / 'quality' / 'reading_content_repairs_101_300_v4.json'
        ),
        'contentRepairs301To500': (
            SOURCE_DATA / 'quality' / 'reading_content_repairs_301_500_v2.json'
        ),
        'contentRepairs501To678': (
            SOURCE_DATA / 'quality' / 'reading_content_repairs_501_678_v1.json'
        ),
        'legacyQuestionBaseSource': (
            SOURCE_DATA / builder.LEGACY_BASE_PRE_FINAL_POLISH_REPAIRS_RELATIVE_PATH
        ),
        'legacyEditorialRepairHistory': (
            SOURCE_DATA / builder.LEGACY_101_300_PRE_POLISH_REPAIRS_RELATIVE_PATH
        ),
        'legacy101To300FinalPolishHistory': (
            SOURCE_DATA
            / builder.LEGACY_101_300_PRE_FINAL_POLISH_REPAIRS_RELATIVE_PATH
        ),
        'legacy301To500FinalPolishHistory': (
            SOURCE_DATA
            / builder.LEGACY_301_500_PRE_FINAL_POLISH_REPAIRS_RELATIVE_PATH
        ),
        'canonicalSourceBaselineV2': SOURCE_DATA / builder.SOURCE_BASELINE_RELATIVE_PATH,
    }
    mapping = SOURCE_DATA / 'mappings' / 'word_pack_reclassification_v1.json'
    if mapping.is_file():
        expected_paths['wordPackMap'] = mapping
    if set(checksums) != set(expected_paths):
        raise ValueError('Source checksum keys are invalid.')
    for key, path in expected_paths.items():
        if checksums.get(key) != builder.source_hash(path):
            raise ValueError(f'Source checksum mismatch: {key}')


def validate_quality_reports(
    sentence_count: int,
    report_records: list[dict[str, Any]],
    translation_missing: list[dict[str, Any]],
    manifest: dict[str, Any],
) -> dict[str, int]:
    translation_report = load(
        SOURCE_DATA / 'reports' / 'reading_translation_audit_v1.json'
    )
    length_report = load(SOURCE_DATA / 'reports' / 'reading_length_audit_v1.json')
    translated = sentence_count - len(translation_missing)
    translation_summary = {
        'totalReadings': 678,
        'totalSentences': sentence_count,
        'sentencesWithTr': translated,
        'sentencesWithoutTr': len(translation_missing),
        'readingsWithCompleteTr': sum(
            record['translationCoverage'] == 1.0 for record in report_records
        ),
        'readingsWithPartialTr': sum(
            0 < record['translationCoverage'] < 1.0 for record in report_records
        ),
        'readingsWithZeroTr': sum(
            record['translationCoverage'] == 0.0 for record in report_records
        ),
        'translationRepairs': manifest['readingEnrichment']['translationRepairs'],
    }
    if translation_report.get('summary') != translation_summary:
        raise ValueError('Translation audit summary is invalid.')
    if translation_report.get('missingSentences') != translation_missing:
        raise ValueError('Translation audit missing-sentence list is invalid.')
    records = length_report.get('readings')
    if not isinstance(records, list) or records != report_records:
        raise ValueError('Reading length audit records are invalid.')
    band_counts = Counter(record['qualityBand'] for record in report_records)
    length_summary = length_report.get('summary')
    if not isinstance(length_summary, dict) or length_summary.get('totalReadings') != 678:
        raise ValueError('Reading length audit summary is invalid.')
    for field, value in {
        'criticalShort': band_counts['critical_short'],
        'short': band_counts['short'],
        'normal': band_counts['normal'],
        'long': band_counts['long'],
    }.items():
        if length_summary.get(field) != value:
            raise ValueError(f'Reading length audit count is invalid: {field}')
    quality_audit = manifest.get('readingQualityAudit')
    if not isinstance(quality_audit, dict) or quality_audit.get('translation') != translation_summary or quality_audit.get('length') != length_summary:
        raise ValueError('Manifest quality-audit metadata is invalid.')
    return {
        'criticalShort': band_counts['critical_short'],
        'criticalShortBefore': int(length_summary.get('criticalShortBefore', 0)),
        'criticalShortRepaired': int(length_summary.get('criticalShortRepaired', 0)),
    }


def validate_legacy_editorial_repair_audit(manifest: dict[str, Any]) -> None:
    pre_polish_repairs = builder.load_content_repairs(
        SOURCE_DATA / builder.LEGACY_101_300_PRE_POLISH_REPAIRS_RELATIVE_PATH
    )
    polished_repairs = builder.load_content_repairs(
        SOURCE_DATA
        / 'legacy'
        / 'reading_content_repairs_101_300_v3_pre_final_polish_history.json'
    )
    range_301_500_repairs = builder.load_content_repairs(
        SOURCE_DATA
        / 'legacy'
        / 'reading_content_repairs_301_500_v1_pre_final_polish_history.json'
    )
    passages = {
        builder.source_number_for(passage): passage
        for passage in canonical_passages().values()
    }
    expected = builder.language_polish_audit(
        pre_polish_repairs, polished_repairs, passages
    )
    actual = load(
        SOURCE_DATA / 'reports' / 'reading_101_300_language_polish_audit_v3.json'
    )
    if actual != expected:
        raise ValueError('101–300 language-polish audit is invalid.')
    if manifest.get('editorialRepairAudit') != expected['summary']:
        raise ValueError('Manifest editorial-repair audit is invalid.')
    expected_301_500 = builder.reading_301_500_editorial_audit(
        passages, range_301_500_repairs
    )
    actual_301_500 = load(
        SOURCE_DATA / 'reports' / 'reading_301_500_editorial_audit_v1.json'
    )
    if actual_301_500 != expected_301_500:
        raise ValueError('301–500 editorial audit is invalid.')
    expected_quality = {
        'repairs101To300V4': builder.production_repair_quality_audit(
            polished_repairs, passages
        )['summary'],
        'repairs301To500V2': builder.production_repair_quality_audit(
            range_301_500_repairs, passages
        )['summary'],
    }
    if manifest.get('productionEditorialQuality') != expected_quality:
        raise ValueError('Production editorial quality metadata is invalid.')


def validate_final_editorial_repair_audit(manifest: dict[str, Any]) -> None:
    base_pre_final_polish_repairs = builder.load_content_repairs(
        SOURCE_DATA / builder.LEGACY_BASE_PRE_FINAL_POLISH_REPAIRS_RELATIVE_PATH
    )
    pre_final_polish_101_300_repairs = builder.load_content_repairs(
        SOURCE_DATA
        / builder.LEGACY_101_300_PRE_FINAL_POLISH_REPAIRS_RELATIVE_PATH
    )
    pre_final_polish_301_500_repairs = builder.load_content_repairs(
        SOURCE_DATA
        / builder.LEGACY_301_500_PRE_FINAL_POLISH_REPAIRS_RELATIVE_PATH
    )
    base_repairs = builder.load_content_repairs(
        SOURCE_DATA / 'quality' / 'reading_content_repairs_v2.json'
    )
    range_101_300_repairs = builder.load_content_repairs(
        SOURCE_DATA / 'quality' / 'reading_content_repairs_101_300_v4.json'
    )
    range_301_500_repairs = builder.load_content_repairs(
        SOURCE_DATA / 'quality' / 'reading_content_repairs_301_500_v2.json'
    )
    range_501_678_repairs = builder.load_content_repairs(
        SOURCE_DATA / 'quality' / 'reading_content_repairs_501_678_v1.json'
    )
    passages = {
        builder.source_number_for(passage): passage
        for passage in canonical_passages().values()
    }
    base_language_audit = builder.language_polish_audit(
        base_pre_final_polish_repairs, base_repairs, passages
    )
    expected_101_300_language = builder.language_polish_audit(
        pre_final_polish_101_300_repairs, range_101_300_repairs, passages
    )
    expected_301_500_language = builder.language_polish_audit(
        pre_final_polish_301_500_repairs, range_301_500_repairs, passages
    )
    expected_language_audit = {
        'schemaVersion': 1,
        'summary': builder.merge_language_polish_summaries([
            base_language_audit,
            expected_101_300_language,
            expected_301_500_language,
        ]),
        'ranges': {
            '101To300': builder.merge_language_polish_summaries([
                base_language_audit,
                expected_101_300_language,
            ]),
            '301To500': expected_301_500_language['summary'],
        },
        'components': {
            'base102And122': base_language_audit,
            '101To300V4': expected_101_300_language,
            '301To500V2': expected_301_500_language,
        },
    }
    if load(
        SOURCE_DATA / 'reports' / 'reading_101_300_language_polish_audit_v4.json'
    ) != expected_101_300_language:
        raise ValueError('101–300 v4 language-polish audit is invalid.')
    if load(
        SOURCE_DATA / 'reports' / 'reading_301_500_language_polish_audit_v2.json'
    ) != expected_301_500_language:
        raise ValueError('301–500 v2 language-polish audit is invalid.')
    if load(
        SOURCE_DATA / 'reports' / 'reading_101_500_final_language_polish_audit_v1.json'
    ) != expected_language_audit:
        raise ValueError('101–500 final language-polish audit is invalid.')
    if manifest.get('editorialRepairAudit') != expected_language_audit['summary']:
        raise ValueError('Manifest editorial-repair audit is invalid.')

    expected_301_500 = builder.reading_301_500_editorial_audit(
        passages, range_301_500_repairs
    )
    if load(
        SOURCE_DATA / 'reports' / 'reading_301_500_editorial_audit_v1.json'
    ) != expected_301_500:
        raise ValueError('301–500 editorial audit is invalid.')
    expected_501_678 = builder.reading_501_678_editorial_audit(
        passages, range_501_678_repairs
    )
    if load(
        SOURCE_DATA / 'reports' / 'reading_501_678_editorial_audit_v1.json'
    ) != expected_501_678:
        raise ValueError('501–678 editorial audit is invalid.')

    all_repairs = builder.load_content_repair_overlays([
        SOURCE_DATA / 'quality' / filename
        for filename in builder.CONTENT_REPAIR_FILENAMES
    ])
    all_quality = builder.production_repair_quality_audit(all_repairs, passages)
    expected_quality = {
        'repairs101To300V4': builder.production_repair_quality_audit(
            base_repairs + range_101_300_repairs, passages
        )['summary'],
        'repairs301To500V2': builder.production_repair_quality_audit(
            range_301_500_repairs, passages
        )['summary'],
        'repairs501To678V1': builder.production_repair_quality_audit(
            range_501_678_repairs, passages
        )['summary'],
        'allProductionOverlays': all_quality['summary'],
    }
    if manifest.get('productionEditorialQuality') != expected_quality:
        raise ValueError('Production editorial quality metadata is invalid.')

    final_passages = copy.deepcopy(passages)
    builder.apply_translation_repairs(
        final_passages,
        builder.load_translation_repairs(
            SOURCE_DATA / 'quality' / 'reading_translation_repairs_v1.json'
        ),
    )
    canonical_language_overlay = builder.load_canonical_language_corrections(
        SOURCE_DATA / 'quality' / builder.CANONICAL_LANGUAGE_CORRECTIONS_FILENAME
    )
    expected_canonical_language_audit = builder.canonical_language_audit_report(
        final_passages, canonical_language_overlay['corrections']
    )
    if load(
        SOURCE_DATA / 'reports' / builder.CANONICAL_LANGUAGE_AUDIT_FILENAME
    ) != expected_canonical_language_audit:
        raise ValueError('Canonical language audit is invalid.')
    if manifest.get('canonicalLanguageQualityAudit') != expected_canonical_language_audit['summary']:
        raise ValueError('Canonical language audit metadata is invalid.')
    canonical_quality_bands = {
        source_number: builder.reading_quality_band(
            passage['level'],
            len(passage['sentences']),
            sum(
                len(builder.english_tokens(sentence['englishText']))
                for sentence in passage['sentences']
            ),
        )
        for source_number, passage in final_passages.items()
    }
    builder.apply_canonical_language_corrections(
        final_passages, canonical_language_overlay['corrections']
    )
    builder.apply_content_repairs(final_passages, base_repairs)
    curated = load_curated_package()
    for source_number, record in curated.items():
        final_passages[source_number]['sentences'] = [
            {
                'index': sentence['index'],
                'englishText': sentence['en'],
                'turkishText': sentence['tr'],
            }
            for sentence in record['sentences']
        ]
        canonical_quality_bands[source_number] = builder.reading_quality_band(
            final_passages[source_number]['level'],
            len(final_passages[source_number]['sentences']),
            sum(
                len(builder.english_tokens(sentence['englishText']))
                for sentence in final_passages[source_number]['sentences']
            ),
        )
    for repairs in (
        range_101_300_repairs,
        range_301_500_repairs,
        range_501_678_repairs,
    ):
        builder.apply_content_repairs(final_passages, repairs)
    expected_final_quality = builder.final_reading_quality_report(
        final_passages,
        canonical_quality_bands,
        all_repairs,
        all_quality,
    )
    if load(
        SOURCE_DATA / 'reports' / 'reading_quality_final_v1.json'
    ) != expected_final_quality:
        raise ValueError('Final reading-quality report is invalid.')
    if manifest.get('finalReadingQualityAudit') != expected_final_quality['summary']:
        raise ValueError('Manifest final reading-quality audit is invalid.')
    expected_language_quality_final = builder.reading_language_quality_final_report(
        final_passages, expected_canonical_language_audit
    )
    if load(
        SOURCE_DATA / 'reports' / builder.LANGUAGE_QUALITY_FINAL_FILENAME
    ) != expected_language_quality_final:
        raise ValueError('Final canonical language-quality report is invalid.')
    if manifest.get('readingLanguageQualityFinal') != expected_language_quality_final['summary']:
        raise ValueError('Final canonical language-quality metadata is invalid.')


def validate(content_dir: Path) -> dict[str, int]:
    manifest = load(content_dir / 'manifest.json')
    validate_source_checksums(manifest)
    validate_canonical_source_baseline()
    validate_final_editorial_repair_audit(manifest)
    generated_question_backup_count = validate_pre_curated_generated_questions_backup()
    curated_package = load_curated_package()
    counts = manifest.get('counts', {})
    if (
        not isinstance(counts, dict)
        or any(counts.get(key) != value for key, value in EXPECTED.items())
        or not isinstance(counts.get('sentences'), int)
        or counts['sentences'] < 1
    ):
        raise ValueError(f'Manifest count mismatch: {counts}')

    words_index = load(content_dir / str(manifest['wordsIndex']))
    words: list[dict[str, Any]] = []
    for pack in words_index.get('packs', []):
        payload = load(content_dir / str(pack['file']))
        entries = payload.get('words', [])
        if payload.get('packId') != pack.get('id') or len(entries) != pack.get('wordCount'):
            raise ValueError('Word pack index is invalid.')
        words.extend(entries)
    if len(words) != EXPECTED['words'] or len({item.get('id') for item in words}) != len(words):
        raise ValueError('Word count or unique word IDs are invalid.')
    if any(not item.get('id') or not item.get('enWord') or not item.get('trMeaning') or not item.get('pos') for item in words):
        raise ValueError('A word lacks required content.')
    word_ids = {str(item['id']) for item in words}

    readings_index = load(content_dir / str(manifest['readingsIndex']))
    readings = readings_index.get('readings', [])
    if len(readings) != EXPECTED['readings'] or len({item.get('id') for item in readings}) != len(readings):
        raise ValueError('Reading count or unique reading IDs are invalid.')

    sentence_count = word_count_readings = duration_readings = focus_word_readings = 0
    summary_readings = question_readings = total_questions = 0
    comprehension_questions = vocabulary_practice_questions = 0
    curated_readings = curated_sentences = curated_questions = 0
    non_curated_readings = 0
    report_records: list[dict[str, Any]] = []
    translation_missing: list[dict[str, Any]] = []
    actual_question_passages: dict[int, dict[str, Any]] = {}
    for item in readings:
        relative_file = str(item['file'])
        payload = load(content_dir / relative_file)
        sentences = payload.get('sentences', [])
        if payload.get('id') != item.get('id') or len(sentences) != item.get('sentenceCount'):
            raise ValueError(f'Invalid reading payload: {item.get("title")}')
        indexes = [sentence.get('index') for sentence in sentences]
        if indexes != sorted(indexes) or len(indexes) != len(set(indexes)):
            raise ValueError(f'Invalid sentence ordering: {item.get("title")}')
        if any(not sentence.get('englishText') for sentence in sentences):
            raise ValueError(f'Blank English sentence: {item.get("title")}')
        enrichment = payload.get('enrichment')
        if not isinstance(enrichment, dict) or enrichment.get('schemaVersion') != 1:
            raise ValueError(f'Missing reading enrichment: {item.get("title")}')
        for key in (
            'displayTitle', 'wordCount', 'estimatedReadingMinutes', 'focusWordIds',
            'summary', 'summaryType', 'questions', 'contentSource',
        ):
            if key not in enrichment:
                raise ValueError(f'Missing enrichment field {key}: {item.get("title")}')
        if not isinstance(enrichment['displayTitle'], str) or not enrichment['displayTitle']:
            raise ValueError(f'Invalid display title: {item.get("title")}')
        if not isinstance(enrichment['wordCount'], int) or enrichment['wordCount'] < 0:
            raise ValueError(f'Invalid word count: {item.get("title")}')
        if not isinstance(enrichment['estimatedReadingMinutes'], int) or enrichment['estimatedReadingMinutes'] < 0:
            raise ValueError(f'Invalid reading duration: {item.get("title")}')
        focus_ids = enrichment['focusWordIds']
        if (
            not isinstance(focus_ids, list)
            or len(focus_ids) > 8
            or len(set(focus_ids)) != len(focus_ids)
            or any(identifier not in word_ids for identifier in focus_ids)
        ):
            raise ValueError(f'Invalid focus words: {item.get("title")}')
        summary = enrichment['summary']
        if summary is not None and (not isinstance(summary, str) or not summary.strip()):
            raise ValueError(f'Invalid extractive summary: {item.get("title")}')
        if enrichment['summaryType'] not in {'curated', 'extractive'}:
            raise ValueError(f'Invalid summary type: {item.get("title")}')
        try:
            source_number = int(enrichment.get('sourceNumber'))
        except (TypeError, ValueError) as error:
            raise ValueError(f'Invalid reading source number: {item.get("title")}') from error
        is_curated = source_number in CURATED_SOURCE_NUMBERS
        questions = enrichment['questions']
        actual_question_passages[source_number] = {
            'enrichment': {'questions': questions}
        }
        if not isinstance(questions, list) or len(questions) > (CURATED_QUESTION_COUNT if is_curated else 3):
            raise ValueError(f'Invalid question collection: {item.get("title")}')
        if is_curated:
            if (
                enrichment.get('contentSource') != 'curated_v2'
                or enrichment['summaryType'] != 'curated'
                or len(sentences) != CURATED_SENTENCE_COUNT
                or len(questions) != CURATED_QUESTION_COUNT
                or not isinstance(enrichment.get('summaryTr'), str)
                or not enrichment['summaryTr'].strip()
            ):
                raise ValueError(f'Curated reading integrity error: {item.get("title")}')
            if any(
                not isinstance(sentence.get('turkishText'), str) or not sentence['turkishText'].strip()
                for sentence in sentences
            ):
                raise ValueError(f'Curated translation missing: {item.get("title")}')
            curated = curated_package[source_number]
            if (
                enrichment['displayTitle'] != curated['replacement_title_en']
                or enrichment.get('turkishTitle') != curated['replacement_title_tr']
                or enrichment['summary'] != curated['summary_en']
                or enrichment['summaryTr'] != curated['summary_tr']
                or [(sentence['index'], sentence['englishText'], sentence['turkishText']) for sentence in sentences]
                != [(sentence['index'], sentence['en'], sentence['tr']) for sentence in curated['sentences']]
                or questions != [curated_question(question, order) for order, question in enumerate(curated['questions'], start=1)]
            ):
                raise ValueError(f'Curated content was changed: {item.get("title")}')
            curated_readings += 1
            curated_sentences += len(sentences)
            curated_questions += len(questions)
        else:
            if enrichment.get('contentSource') != 'derived_v1' or enrichment['summaryType'] != 'extractive':
                raise ValueError(f'Derived reading metadata is invalid: {item.get("title")}')
            non_curated_readings += 1
        for expected_order, question in enumerate(questions, start=1):
            if (
                not isinstance(question, dict)
                or not question.get('id')
                or question.get('sortOrder') != expected_order
                or not isinstance(question.get('question'), str)
                or len(question.get('options', [])) != 4
                or len(set(question['options'])) != 4
                or not isinstance(question.get('correctOptionIndex'), int)
                or not 0 <= question['correctOptionIndex'] < 4
                or not isinstance(question.get('explanation'), str)
                or question.get('questionCategory') not in {'comprehension', 'vocabulary_practice'}
            ):
                raise ValueError(f'Invalid reading question: {item.get("title")}')
            if is_curated and question['questionCategory'] != 'comprehension':
                raise ValueError('Curated questions must remain comprehension questions.')
            if not is_curated and (
                question['questionCategory'] != 'vocabulary_practice'
                or question.get('type') != 'vocabulary_cloze'
                or not str(question.get('question', '')).startswith('Complete sentence ')
                or not isinstance(question.get('questionTr'), str)
                or not question['questionTr'].strip()
                or not isinstance(question.get('answerEn'), str)
                or not question['answerEn'].strip()
                or not isinstance(question.get('explanationTr'), str)
                or not question['explanationTr'].strip()
            ):
                raise ValueError('Derived questions must be bilingual vocabulary practice.')
            comprehension_questions += int(question['questionCategory'] == 'comprehension')
            vocabulary_practice_questions += int(question['questionCategory'] == 'vocabulary_practice')
        word_count = sum(len(builder.english_tokens(sentence['englishText'])) for sentence in sentences)
        if word_count != enrichment['wordCount']:
            raise ValueError(f'Reading word count is invalid: {item.get("title")}')
        translated_count = sum(bool(builder.clean(sentence.get('turkishText'))) for sentence in sentences)
        for sentence in sentences:
            if builder.clean(sentence.get('turkishText')):
                continue
            translation_missing.append({
                'sourceNumber': source_number,
                'readingId': item['id'],
                'sentenceIndex': sentence['index'],
                'englishText': sentence['englishText'],
            })
        quality_band = builder.reading_quality_band(item.get('level'), len(sentences), word_count)
        report_records.append({
            'sourceNumber': source_number,
            'level': item.get('level'),
            'sentenceCount': len(sentences),
            'wordCount': word_count,
            'estimatedMinutes': enrichment['estimatedReadingMinutes'],
            'translationCoverage': round(translated_count / len(sentences), 6) if sentences else 1.0,
            'qualityBand': quality_band,
            'wasCriticalShort': None,
            'contentRepairApplied': None,
        })
        sentence_count += len(sentences)
        word_count_readings += int(word_count > 0)
        duration_readings += int(enrichment['estimatedReadingMinutes'] > 0)
        focus_word_readings += int(bool(focus_ids))
        summary_readings += int(summary is not None)
        question_readings += int(bool(questions))
        total_questions += len(questions)
    if sentence_count != counts['sentences']:
        raise ValueError(f"Sentence count mismatch: expected {counts['sentences']}, got {sentence_count}")
    if (curated_readings, curated_sentences, curated_questions, non_curated_readings) != (100, 1500, 500, 578):
        raise ValueError('Curated/non-curated reading coverage is invalid.')
    frozen_question_passages = {
        builder.source_number_for(passage): passage
        for passage in canonical_passages().values()
    }
    builder.apply_content_repairs(
        frozen_question_passages,
        builder.load_content_repairs(
            SOURCE_DATA / builder.LEGACY_BASE_PRE_FINAL_POLISH_REPAIRS_RELATIVE_PATH
        ),
    )
    builder.apply_content_repairs(
        frozen_question_passages,
        builder.load_content_repairs(
            SOURCE_DATA / builder.LEGACY_101_300_PRE_POLISH_REPAIRS_RELATIVE_PATH
        ),
    )
    expected_question_hash = builder.question_payload_hash(
        frozen_question_passages, curated_package
    )
    actual_question_hash = builder.generated_question_payload_hash(
        actual_question_passages
    )
    expected_question_integrity = {
        'schemaVersion': 1,
        'payloadSha256': expected_question_hash,
        'curatedReadings': 100,
        'derivedReadings': 578,
    }
    if actual_question_hash != expected_question_hash:
        raise ValueError('Generated questions no longer match their frozen sources.')
    if manifest.get('readingQuestionIntegrity') != expected_question_integrity:
        raise ValueError('Question-integrity metadata is invalid.')

    expected_enrichment = {
        'schemaVersion': 1,
        'wordsPerMinute': builder.READING_WORDS_PER_MINUTE,
        'wordCountReadings': word_count_readings,
        'durationReadings': duration_readings,
        'focusWordReadings': focus_word_readings,
        'summaryReadings': summary_readings,
        'questionReadings': question_readings,
        'totalQuestions': total_questions,
        'comprehensionQuestions': comprehension_questions,
        'vocabularyPracticeQuestions': vocabulary_practice_questions,
        'curatedReadings': curated_readings,
        'curatedSentences': curated_sentences,
        'curatedQuestions': curated_questions,
        'translationRepairs': len(builder.load_translation_repairs(
            SOURCE_DATA / 'quality' / 'reading_translation_repairs_v1.json'
        )),
        'contentRepairs': len(builder.load_content_repair_overlays([
            SOURCE_DATA / 'quality' / filename
            for filename in builder.CONTENT_REPAIR_FILENAMES
        ])),
    }
    if manifest.get('readingEnrichment') != expected_enrichment:
        raise ValueError('Reading enrichment manifest is invalid.')

    report_records.sort(key=lambda record: record['sourceNumber'])
    length_report = load(SOURCE_DATA / 'reports' / 'reading_length_audit_v1.json')
    generated_records = length_report.get('readings')
    if not isinstance(generated_records, list) or len(generated_records) != 678:
        raise ValueError('Reading length audit records are missing.')
    for expected, generated in zip(report_records, generated_records):
        for key in (
            'sourceNumber', 'level', 'sentenceCount', 'wordCount',
            'estimatedMinutes', 'translationCoverage', 'qualityBand',
        ):
            if generated.get(key) != expected[key]:
                raise ValueError(f'Reading length audit record is invalid: {key}')
        if not isinstance(generated.get('wasCriticalShort'), bool) or not isinstance(generated.get('contentRepairApplied'), bool):
            raise ValueError('Reading length audit repair flags are invalid.')
        expected_status = (
            'unrecoverable_source_missing' if expected['sentenceCount'] == 0
            else ('repaired' if generated['contentRepairApplied'] else None)
        )
        if generated.get('repairStatus') != expected_status:
            raise ValueError('Reading length audit repair status is invalid.')
        expected['wasCriticalShort'] = generated['wasCriticalShort']
        expected['contentRepairApplied'] = generated['contentRepairApplied']
        expected['repairStatus'] = expected_status
    quality_counts = validate_quality_reports(
        sentence_count, report_records, translation_missing, manifest
    )

    dictionary_index = load(content_dir / str(manifest['dictionaryIndex']))
    if dictionary_index.get('contentVersion') != manifest.get('contentVersion'):
        raise ValueError('Dictionary content version mismatch.')
    shards = dictionary_index.get('shards', [])
    if not isinstance(shards, list) or not shards:
        raise ValueError('Dictionary shard index is missing.')
    records: list[dict[str, Any]] = []
    for shard in shards:
        if not isinstance(shard, dict):
            raise ValueError('Dictionary shard metadata is invalid.')
        shard_records = load(content_dir / str(shard.get('file'))) .get('records', [])
        data = (content_dir / str(shard.get('file'))).read_bytes()
        if (
            not isinstance(shard_records, list)
            or len(shard_records) != shard.get('recordCount')
            or hashlib.sha256(data).hexdigest() != shard.get('checksum')
            or len(data) != shard.get('sizeBytes')
        ):
            raise ValueError('Dictionary shard is invalid.')
        records.extend(shard_records)
    keys = [normalized_dictionary_key(record.get('enWord')) for record in records]
    if any(
        not record.get('id')
        or not record.get('enWord')
        or not record.get('trMeaning')
        or record.get('normalizedKey') != normalized_dictionary_key(record.get('enWord'))
        for record in records
    ):
        raise ValueError('Dictionary record is invalid.')
    duplicate_normalized_keys = len(keys) - len(set(keys))
    if dictionary_index.get('recordCount') != len(records):
        raise ValueError('Dictionary record count is invalid.')
    if dictionary_index.get('uniqueNormalizedHeadwords') != len(set(keys)):
        raise ValueError('Dictionary headword count is invalid.')
    if dictionary_index.get('duplicateNormalizedKeys') != duplicate_normalized_keys:
        raise ValueError('Dictionary duplicate-key count is invalid.')

    return {
        'words': len(words),
        'readings': len(readings),
        'sentences': sentence_count,
        'dictionaryEntries': len(records),
        'dictionaryHeadwords': len(set(keys)),
        'dictionaryDuplicateNormalizedKeys': duplicate_normalized_keys,
        'dictionaryShards': len(shards),
        'orphanSentences': 0,
        'readingWordCountCoverage': word_count_readings,
        'readingDurationCoverage': duration_readings,
        'readingFocusWordCoverage': focus_word_readings,
        'readingSummaryCoverage': summary_readings,
        'readingQuestionCoverage': question_readings,
        'totalQuestions': total_questions,
        'comprehensionQuestions': comprehension_questions,
        'vocabularyPracticeQuestions': vocabulary_practice_questions,
        'curatedReadings': curated_readings,
        'curatedSentences': curated_sentences,
        'curatedQuestions': curated_questions,
        'canonicalSourceBaselineVerified': 578,
        'preCuratedGeneratedQuestionsBackedUp': generated_question_backup_count,
        **quality_counts,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description='Validate public PASSAGETR static content.')
    parser.add_argument('--content-dir', type=Path, default=ROOT / 'assets' / 'content' / 'v1')
    args = parser.parse_args()
    counts = validate(args.content_dir.resolve())
    print(json.dumps(counts, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
