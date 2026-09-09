#!/usr/bin/env python3
"""Validate the public PASSAGETR static-content contract.

The production prose contract is intentionally small: word records come from
one canonical CSV, and every generated reading sentence and question comes
from the single canonical 800-reading Excel workbook.
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import build_static_content as builder  # noqa: E402


SOURCE = ROOT / 'source_data'
CONTENT = ROOT / 'assets' / 'content' / 'v1'
WORDS_SOURCE = SOURCE / 'canonical' / 'words' / builder.WORDS_CANONICAL_FILENAME
READINGS_WORKBOOK = (
    SOURCE / 'canonical' / 'readings' / builder.READINGS_CANONICAL_FILENAME
)
LEGACY_MAP_SOURCE = SOURCE / builder.READINGS_LEGACY_MAP_RELATIVE_PATH
DICTIONARY_SOURCE = SOURCE / 'canonical' / 'dictionary' / 'dictionary_tr_en.xlsx'
STUDY_SOURCE = SOURCE / 'canonical' / 'study' / 'PASSAGETR_YDS_Study_Canonical_v2_Module_01-30.xlsx'
TEST_BANK_SOURCE = SOURCE / 'canonical' / 'passagetr_test_bank_CANONICAL_v3.xlsx'

EXPECTED_WORDS = 9000
EXPECTED_READINGS = 800
EXPECTED_SENTENCES = 7500
EXPECTED_QUESTIONS = 4000
EXPECTED_WORD_TAGS = 66
EXPECTED_DICTIONARY_ENTRIES = 121772
EXPECTED_DICTIONARY_HEADWORDS = 121501
WORD_FIELDS = {
    'en_word', 'tr_meaning', 'pos', 'example_en', 'example_tr',
    'synonyms_raw', 'antonyms_raw', 'level', 'tags_raw', 'notes',
}
REQUIRED_WORD_FIELDS = (
    'en_word', 'tr_meaning', 'pos', 'example_en', 'example_tr',
    'level', 'tags_raw',
)


def fail(message: str) -> None:
    raise ValueError(message)


def load_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(payload, dict):
        fail(f'JSON object expected: {path.relative_to(ROOT)}')
    return payload


def canonical_readings() -> tuple[dict[int, dict[str, Any]], int, int, list[int]]:
    """Independently reload the workbook and return readings plus totals."""
    readings = builder.load_reading_workbook(READINGS_WORKBOOK)
    sentence_rows = sum(len(item['sentences']) for item in readings.values())
    question_rows = sum(len(item['questions']) for item in readings.values())
    if sentence_rows != EXPECTED_SENTENCES:
        fail(f'Expected {EXPECTED_SENTENCES} workbook sentences, got {sentence_rows}')
    if question_rows != EXPECTED_QUESTIONS:
        fail(f'Expected {EXPECTED_QUESTIONS} workbook questions, got {question_rows}')
    source_missing = [
        number for number, item in readings.items() if not item['sentences']
    ]
    return readings, sentence_rows, question_rows, source_missing


def validate_words() -> dict[str, int]:
    canonical_sources = sorted(WORDS_SOURCE.parent.glob('*.csv'))
    if canonical_sources != [WORDS_SOURCE]:
        fail('Canonical words directory must contain only the active CSV source.')
    rows = builder.read_csv(WORDS_SOURCE)
    if len(rows) != EXPECTED_WORDS:
        fail(f'Expected {EXPECTED_WORDS} canonical word rows, got {len(rows)}')
    if not rows or set(rows[0]) != WORD_FIELDS:
        fail('Canonical word CSV headers do not match the required contract.')
    headwords: set[str] = set()
    canonical_tags: set[str] = set()
    invalid_tags = 0
    spreadsheet_errors = 0
    for row_number, row in enumerate(rows, start=2):
        if set(row) != WORD_FIELDS:
            fail(f'Unexpected word fields at CSV row {row_number}.')
        if any(not builder.clean(row[field]) for field in REQUIRED_WORD_FIELDS):
            fail(f'Blank required word field at CSV row {row_number}.')
        key = builder.normalized(row['en_word'])
        if key in headwords:
            fail(f'Duplicate canonical headword at CSV row {row_number}: {row["en_word"]!r}')
        headwords.add(key)
        try:
            builder.canonical_pos(row['pos'])
        except ValueError as error:
            raise ValueError(f'Invalid canonical POS at CSV row {row_number}.') from error
        try:
            level = builder.canonical_level(
                row['level'], kind='word', where=f'CSV row {row_number}'
            )
        except ValueError as error:
            raise ValueError(f'Invalid canonical word level at CSV row {row_number}.') from error
        if level not in builder.CANONICAL_LEVELS:
            fail(f'Non-canonical word level at CSV row {row_number}.')
        tags = builder.parse_tag_list(row['tags_raw'])
        if not tags or any(not builder.is_canonical_word_tag(tag) for tag in tags):
            invalid_tags += 1
        spreadsheet_errors += sum(
            len(builder.invalid_spreadsheet_tokens(value)) for value in row.values()
        )
        canonical_tags.update(tags)
    if invalid_tags:
        fail(f'Invalid canonical word tags: {invalid_tags}')
    if spreadsheet_errors:
        fail(f'Spreadsheet error tokens in canonical word CSV: {spreadsheet_errors}')
    if len(headwords) != EXPECTED_WORDS:
        fail('Canonical word headwords are not unique.')
    if len(canonical_tags) != EXPECTED_WORD_TAGS:
        fail(
            f'Canonical word taxonomy must contain {EXPECTED_WORD_TAGS} tags, '
            f'got {len(canonical_tags)}.'
        )
    return {
        'rows': len(rows),
        'uniqueHeadwords': len(headwords),
        'invalidTags': invalid_tags,
        'spreadsheetErrors': spreadsheet_errors,
        'canonicalTags': len(canonical_tags),
    }


def validate_no_stale_reference() -> int:
    canonical_sources = sorted(WORDS_SOURCE.parent.glob('*.csv'))
    if canonical_sources != [WORDS_SOURCE]:
        fail('Stale canonical word-source files remain.')
    return 0


def validate_no_sentence_overlay_sources() -> int:
    # The complete tracked source-data allowlist intentionally contains no
    # repair/override layer.  The single reading source is the workbook, so a
    # reappearing passage/sentence/question CSV or JSON fails the build.
    allowed = {
        WORDS_SOURCE.resolve(), READINGS_WORKBOOK.resolve(),
        LEGACY_MAP_SOURCE.resolve(), DICTIONARY_SOURCE.resolve(),
        STUDY_SOURCE.resolve(), TEST_BANK_SOURCE.resolve(),
    }
    files = {path.resolve() for path in SOURCE.rglob('*') if path.is_file()}
    unexpected = sorted(files - allowed)
    if unexpected:
        relative = ', '.join(str(path.relative_to(ROOT)) for path in unexpected)
        fail(f'Unexpected non-canonical source-data files remain: {relative}')
    return 0


def validate_generated_content(
    readings: dict[int, dict[str, Any]],
    sentence_rows: int,
    question_rows: int,
    source_missing: list[int],
) -> dict[str, Any]:
    manifest = load_json(CONTENT / 'manifest.json')
    counts = manifest.get('counts')
    if counts != {
        'words': EXPECTED_WORDS,
        'readings': EXPECTED_READINGS,
        'sentences': EXPECTED_SENTENCES,
        'dictionaryEntries': EXPECTED_DICTIONARY_ENTRIES,
        'dictionaryHeadwords': EXPECTED_DICTIONARY_HEADWORDS,
    }:
        fail(f'Unexpected manifest counts: {counts!r}')
    source = manifest.get('readingCanonicalSource')
    if source != {
        'workbook': 'canonical/readings/PASSAGETR_READINGS_CANONICAL_800_FINAL.xlsx',
        'productionSentenceOverlays': 0,
        'sourceMissingReadingNumbers': source_missing,
    }:
        fail(f'Unexpected reading canonical source declaration: {source!r}')
    integrity = manifest.get('readingQuestionIntegrity')
    if not isinstance(integrity, dict) or integrity.get('schemaVersion') != 1:
        fail('Reading question integrity declaration is invalid.')
    checksums = manifest.get('sourceChecksums')
    expected_checksums = {
        'words': builder.source_hash(WORDS_SOURCE),
        'readingsWorkbook': builder.source_hash(READINGS_WORKBOOK),
        'dictionary': builder.source_hash(DICTIONARY_SOURCE),
    }
    if checksums != expected_checksums:
        fail('Manifest source checksums do not describe the canonical inputs.')

    words_index = load_json(CONTENT / 'words' / 'index.json')
    generated_words: list[dict[str, Any]] = []
    for pack in words_index.get('packs', []):
        generated_words.extend(load_json(CONTENT / str(pack['file']))['words'])
    if len(generated_words) != EXPECTED_WORDS:
        fail('Generated word count does not match canonical CSV.')
    word_headwords = {builder.normalized(word.get('enWord')) for word in generated_words}
    if len(word_headwords) != EXPECTED_WORDS:
        fail('Generated word headwords are not unique.')
    if any(builder.has_invalid_spreadsheet_token(str(value)) for word in generated_words for value in word.values()):
        fail('Generated word JSON contains a spreadsheet error token.')
    generated_tags = {
        tag
        for word in generated_words
        for tag in word.get('tags', [])
        if isinstance(tag, str)
    }
    if (
        len(generated_tags) != EXPECTED_WORD_TAGS
        or any(not builder.is_canonical_word_tag(tag) for tag in generated_tags)
    ):
        fail('Generated word JSON does not preserve the canonical tag taxonomy.')
    generated_levels = {
        word.get('level') for word in generated_words if word.get('level')
    }
    if not generated_levels <= set(builder.CANONICAL_LEVELS):
        fail(f'Generated word levels are not canonical: {sorted(generated_levels)}')

    index = load_json(CONTENT / 'readings' / 'index.json').get('readings')
    if not isinstance(index, list) or len(index) != EXPECTED_READINGS:
        fail('Generated reading index is incomplete.')
    indexed_numbers: set[int] = set()
    total_sentences = 0
    total_questions = 0
    question_payload: list[dict[str, Any]] = []
    for entry in index:
        if not isinstance(entry, dict):
            fail('Generated reading index entry is invalid.')
        number = int(entry.get('sourceNumber'))
        if number in indexed_numbers or number not in readings:
            fail('Generated reading index source-number coverage is invalid.')
        indexed_numbers.add(number)
        expected_record = readings[number]
        item = load_json(CONTENT / str(entry['file']))
        expected_id = builder.reading_id(number)
        if item.get('id') != expected_id or entry.get('id') != expected_id:
            fail(f'Generated reading ID drift at {number:03d}.')
        expected_title = (
            f'{number:03d} - {expected_record["title_en"]} '
            f'({expected_record["title_tr"]})'
        )
        if item.get('title') != expected_title or entry.get('title') != expected_title:
            fail(f'Generated reading title drift at {number:03d}.')
        if entry.get('level') not in builder.CANONICAL_LEVELS:
            fail(f'Non-canonical reading level at {number:03d}.')
        expected_sentences = [
            {'index': item['index'], 'englishText': item['englishText'],
             'turkishText': item['turkishText']}
            for item in expected_record['sentences']
        ]
        if item.get('sentences') != expected_sentences:
            fail(f'Generated EN/TR body is not workbook text at {number:03d}.')
        total_sentences += len(expected_sentences)
        questions = item.get('enrichment', {}).get('questions')
        if questions != expected_record['questions']:
            fail(f'Generated questions drifted at {number:03d}.')
        total_questions += len(questions)
        question_payload.append({'sourceNumber': number, 'questions': questions})
    if indexed_numbers != set(readings) or total_sentences != sentence_rows:
        fail('Generated reading index/body coverage does not match the workbook.')
    if total_questions != question_rows:
        fail('Generated reading question coverage does not match the workbook.')
    payload_hash = hashlib.sha256(
        builder.json_bytes(question_payload)
    ).hexdigest()
    if integrity.get('payloadSha256') != payload_hash:
        fail('Reading question integrity hash does not match generated questions.')
    if integrity.get('readings') != EXPECTED_READINGS:
        fail('Reading question integrity reading count is invalid.')
    if integrity.get('questions') != EXPECTED_QUESTIONS:
        fail('Reading question integrity question count is invalid.')

    legacy_map_path = manifest.get('legacyReadingIdMap')
    if legacy_map_path != 'readings/legacy_id_map.json':
        fail('Legacy reading ID map declaration is invalid.')
    legacy_map = load_json(CONTENT / str(legacy_map_path))
    mapping = legacy_map.get('mapping')
    if not isinstance(mapping, dict) or len(mapping) != 678:
        fail('Legacy reading ID map must contain 678 entries.')
    expected_mapping = builder.load_legacy_reading_id_map(LEGACY_MAP_SOURCE)
    for old_id, number_text in expected_mapping.items():
        if mapping.get(old_id) != builder.reading_id(int(number_text)):
            fail('Legacy reading ID map drift detected.')

    dictionary = load_json(CONTENT / 'dictionary' / 'index.json')
    if (
        dictionary.get('recordCount') != EXPECTED_DICTIONARY_ENTRIES
        or dictionary.get('uniqueNormalizedHeadwords') != EXPECTED_DICTIONARY_HEADWORDS
    ):
        fail('Generated dictionary index count is invalid.')
    return {
        'generatedWords': len(generated_words),
        'generatedReadings': len(indexed_numbers),
        'generatedSentences': total_sentences,
        'generatedWordTags': len(generated_tags),
        'productionSentenceOverlays': 0,
    }


def main() -> int:
    for path in (
        WORDS_SOURCE, READINGS_WORKBOOK, LEGACY_MAP_SOURCE, DICTIONARY_SOURCE,
        STUDY_SOURCE, CONTENT / 'manifest.json',
    ):
        if not path.is_file():
            fail(f'Missing required source/content file: {path.relative_to(ROOT)}')
    words = validate_words()
    readings, sentence_rows, question_rows, source_missing = canonical_readings()
    overlays = validate_no_sentence_overlay_sources()
    stale_references = validate_no_stale_reference()
    generated = validate_generated_content(
        readings, sentence_rows, question_rows, source_missing
    )
    print(json.dumps({
        'words': words,
        'readings': {
            'records': len(readings),
            'canonicalSentenceRows': sentence_rows,
            'canonicalQuestions': question_rows,
            'blankEnglish': 0,
            'blankTurkish': 0,
            'sourceMissing': source_missing,
        },
        'generated': generated,
        'productionSentenceOverlays': overlays,
        'staleOldWordSourceReferences': stale_references,
    }, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(f'VALIDATION_ERROR: {error}', file=sys.stderr)
        raise SystemExit(1)
