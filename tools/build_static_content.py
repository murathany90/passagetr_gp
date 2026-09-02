#!/usr/bin/env python3
"""Build PASSAGETR's public, bundled content from audited local sources.

The builder normalizes and partitions source data. The curated 001--100
package is copied without altering its bilingual sentences, titles, summaries,
or questions. Other readings retain deterministic study metadata. The Excel
dictionary is a build-time input; Flutter reads only the JSON assets produced
here.
"""

from __future__ import annotations

import argparse
import copy
import csv
import hashlib
import json
import re
import shutil
import uuid
import xml.etree.ElementTree as ET
import zipfile
from collections import Counter, defaultdict
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Iterator


ROOT = Path(__file__).resolve().parents[1]
ID_NAMESPACE = uuid.UUID('07cbf023-3cd8-4ae7-a892-097112e35d7f')
DICTIONARY_SHARD_TARGET_BYTES = 1_500_000
# The application shows this as an estimate, not a source-provided duration.
# 200 words/minute is a stable, middle-of-range English reading rate.
READING_WORDS_PER_MINUTE = 200
SMART_QUOTES = str.maketrans({
    '\u2018': "'", '\u2019': "'", '\u201c': '"', '\u201d': '"',
    '\u00a0': ' ', '\ufeff': '',
})
HYPHENS = str.maketrans({
    '\u2010': '-', '\u2011': '-', '\u2012': '-', '\u2013': '-',
    '\u2014': '-', '\u2212': '-',
})
POS_ALIASES = {
    'prep': 'prep.', 'preposition': 'prep.', 'prepositional phrase': 'prep.',
    'prep phr': 'prep.', 'prepositional phr': 'prep.',
    'phrasal verb': 'phr. v.', 'phrasal v': 'phr. v.', 'phr v': 'phr. v.',
    'verb': 'v.', 'v': 'v.', 'noun': 'n.', 'n': 'n.',
    'adjective': 'adj.', 'adj': 'adj.', 'adverb': 'adv.', 'adv': 'adv.',
    'np': 'NP', 'proper noun': 'NP', 'conjunction': 'conj.', 'conj': 'conj.',
    'determiner': 'det.', 'det': 'det.', 'modal': 'modal', 'modal verb': 'modal',
}
POS_ORDER = ('prep.', 'phr. v.', 'v.', 'n.', 'adj.', 'adv.', 'NP', 'conj.', 'det.', 'modal')
WORD_TOKEN = re.compile(r"[A-Za-z]+(?:['-][A-Za-z]+)*")
TITLE_PATTERN = re.compile(
    r'^\s*(?:(?P<number>\d+)\s*[-.)]\s*)?(?P<english>.*?)(?:\s*\((?P<turkish>[^()]*)\))?\s*$'
)
STOP_WORDS = frozenset({
    'a', 'about', 'after', 'all', 'also', 'am', 'an', 'and', 'are', 'as', 'at',
    'be', 'been', 'being', 'by', 'can', 'could', 'did', 'do', 'does', 'for',
    'from', 'had', 'has', 'have', 'he', 'her', 'here', 'him', 'his', 'i', 'if',
    'in', 'into', 'is', 'it', 'its', 'may', 'me', 'more', 'most', 'my', 'no',
    'not', 'of', 'on', 'one', 'or', 'our', 'out', 'she', 'should', 'so', 'some',
    'such', 'than', 'that', 'the', 'their', 'them', 'then', 'there', 'these',
    'they', 'this', 'those', 'to', 'too', 'was', 'we', 'were', 'what', 'when',
    'which', 'who', 'will', 'with', 'would', 'you', 'your',
})
DEFAULT_CURATED_READINGS_RELATIVE_PATH = Path(
    'curated/readings_001_100_curated_v2.json'
)
QUALITY_DIRECTORY = Path('quality')
REPORTS_DIRECTORY = Path('reports')
CANONICAL_LANGUAGE_CORRECTIONS_FILENAME = (
    'reading_canonical_language_corrections_v1.json'
)
CANONICAL_LANGUAGE_CORRECTION_FILENAMES = (
    CANONICAL_LANGUAGE_CORRECTIONS_FILENAME,
    'reading_canonical_language_corrections_101_300_v3.json',
)
CANONICAL_LANGUAGE_AUDIT_FILENAME = 'reading_canonical_language_audit_v1.json'
CANONICAL_EDITORIAL_REVIEW_101_300_FILENAME = (
    'reading_canonical_editorial_review_101_300_v1.json'
)
WORD_TR_MEANING_CORRECTIONS_FILENAME = 'word_tr_meaning_corrections_v1.json'
WORD_CONTENT_QUALITY_AUDIT_FILENAME = 'word_content_quality_audit_v1.json'
INVALID_SPREADSHEET_TOKENS = (
    '#AD?', '#NAME?', '#N/A', '#VALUE!', '#REF!', '#DIV/0!', '#NUM!', '#NULL!',
    '#YOK', '#YOK?', '#DE\u011eER!', '#BA\u015eV!', '#SAYI!', '#B\u00d6L/0!',
)
LANGUAGE_QUALITY_FINAL_FILENAME = 'reading_language_quality_final_v1.json'
# The prior sentence-first audit remains published for historical comparison.
HISTORICAL_CRITICAL_SHORT_COUNT = 322
CONTENT_REPAIR_FILENAMES = (
    'reading_content_repairs_v2.json',
    'reading_content_repairs_101_300_v4.json',
    'reading_content_repairs_301_500_v2.json',
    'reading_content_repairs_501_678_v1.json',
)
LEGACY_BASE_PRE_FINAL_POLISH_REPAIRS_RELATIVE_PATH = Path(
    'legacy/reading_content_repairs_v1_pre_final_polish_history.json'
)
LEGACY_101_300_PRE_POLISH_REPAIRS_RELATIVE_PATH = Path(
    'legacy/reading_content_repairs_101_300_v2_language_pre_polish_history.json'
)
LEGACY_101_300_PRE_FINAL_POLISH_REPAIRS_RELATIVE_PATH = Path(
    'legacy/reading_content_repairs_101_300_v3_pre_final_polish_history.json'
)
LEGACY_301_500_PRE_FINAL_POLISH_REPAIRS_RELATIVE_PATH = Path(
    'legacy/reading_content_repairs_301_500_v1_pre_final_polish_history.json'
)
SOURCE_BASELINE_RELATIVE_PATH = Path(
    'baselines/readings_101_678_source_baseline_v2.json'
)
GENERIC_FOCUS_WORDS = frozenset({
    'because', 'different', 'good', 'idea', 'people', 'place', 'problem',
    'thing', 'things', 'time', 'topic', 'way', 'work', 'world', 'year',
})
FORBIDDEN_EDITORIAL_TEMPLATE_PREFIXES = (
    'in the discussion of ',
    'the passage develops ',
    'this observation gives ',
    'one important part of ',
    'the reader can connect ',
    'the description of ',
    'this point helps explain ',
    'the account asks readers to keep ',
    'this passage shows ',
    'this detail ',
    'this point ',
    'the reader can see ',
    'this observation ',
)


def clean(value: str | None) -> str:
    text = (value or '').translate(SMART_QUOTES).replace('\r', ' ').replace('\n', ' ')
    text = re.sub(r'[\u200b\u200c\u200d]', '', text)
    return re.sub(r'\s+', ' ', text).strip()


def invalid_spreadsheet_tokens(value: str | None) -> list[str]:
    """Return known spreadsheet-error tokens embedded in user-visible text."""
    text = clean(value).casefold()
    return [
        token for token in INVALID_SPREADSHEET_TOKENS
        if token.casefold() in text
    ]


def has_invalid_spreadsheet_token(value: str | None) -> bool:
    return bool(invalid_spreadsheet_tokens(value))


def normalized(value: str | None) -> str:
    return clean(value).lower()


def normalize_dictionary_key(value: str | None) -> str:
    """The documented runtime key: trim/lower/apostrophe/hyphen/whitespace."""
    return re.sub(r'\s+', ' ', clean(value).translate(HYPHENS)).strip().lower()


def canonical_pos(raw: str | None) -> str:
    candidates = [clean(item) for item in re.split(r'[;,]', clean(raw))]
    mapped: list[str] = []
    for item in candidates:
        if not item:
            continue
        key = re.sub(r'\s+', ' ', item.lower().replace('.', ' ')).strip()
        value = POS_ALIASES.get(key)
        if value is None:
            raise ValueError(f'Unsupported part of speech: {item!r}')
        mapped.append(value)
    if not mapped:
        raise ValueError('Empty part of speech')
    return ';'.join(value for value in POS_ORDER if value in set(mapped))


def deterministic_id(kind: str, value: str) -> str:
    return str(uuid.uuid5(ID_NAMESPACE, f'{kind}|{normalized(value)}'))


def pack_id(name: str) -> str:
    return deterministic_id('pack', name)


def word_id(word: str, pos: str) -> str:
    return deterministic_id('word', f'yds set 001|{normalized(word)}|{normalized(pos)}')


def passage_id(title: str) -> str:
    return deterministic_id('passage', title)


def dictionary_entry_id(key: str, pos: str | None, meaning: str) -> str:
    material = f'{key}\u241f{normalized(pos)}\u241f{normalized(meaning)}'
    return hashlib.sha256(material.encode('utf-8')).hexdigest()


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open('r', encoding='utf-8-sig', newline='') as handle:
        return list(csv.DictReader(handle, delimiter=';'))


def source_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def json_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, separators=(',', ':')).encode('utf-8')


def write_json(path: Path, value: Any) -> bytes:
    data = json_bytes(value)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return data


def nullable(value: str | None) -> str | None:
    value = clean(value)
    return value or None


def parse_tag_list(value: str | None) -> list[str]:
    return [item for item in (clean(part) for part in (value or '').split(';')) if item]


def curated_text(record: dict[str, Any], field: str) -> str:
    value = record.get(field)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f'Curated reading lacks {field!r}')
    return value


def load_curated_readings(path: Path) -> dict[int, dict[str, Any]]:
    """Load the immutable bilingual 001–100 editorial package unchanged."""
    raw = json.loads(path.read_text(encoding='utf-8'))
    records = raw.get('readings', raw) if isinstance(raw, dict) else raw
    if not isinstance(records, list) or len(records) != 100:
        raise ValueError('Curated package must contain exactly 100 readings.')
    result: dict[int, dict[str, Any]] = {}
    for record in records:
        if not isinstance(record, dict):
            raise ValueError('Curated reading must be an object.')
        try:
            number = int(record.get('source_number'))
        except (TypeError, ValueError) as error:
            raise ValueError('Curated reading has an invalid source_number.') from error
        if not 1 <= number <= 100 or number in result:
            raise ValueError(f'Invalid curated source number: {number}')
        sentences = record.get('sentences')
        questions = record.get('questions')
        if (
            not isinstance(sentences, list)
            or len(sentences) != 15
            or [item.get('index') for item in sentences] != list(range(1, 16))
            or not isinstance(questions, list)
            or len(questions) != 5
        ):
            raise ValueError(f'Invalid curated record {number:03d}')
        for sentence in sentences:
            if not isinstance(sentence, dict):
                raise ValueError(f'Invalid curated sentence in {number:03d}')
            curated_text(sentence, 'en')
            curated_text(sentence, 'tr')
        for question in questions:
            if not isinstance(question, dict):
                raise ValueError(f'Invalid curated question in {number:03d}')
            for field in (
                'id', 'type', 'question_en', 'question_tr', 'answer_en',
                'answer_tr', 'explanation_en', 'explanation_tr',
            ):
                curated_text(question, field)
            if (
                not isinstance(question.get('options_en'), list)
                or not isinstance(question.get('options_tr'), list)
                or len(question['options_en']) != 4
                or len(question['options_tr']) != 4
                or not isinstance(question.get('correct_option_index'), int)
                or not 0 <= question['correct_option_index'] < 4
                or not isinstance(question.get('evidence_sentence_indexes'), list)
                or not question['evidence_sentence_indexes']
            ):
                raise ValueError(f'Invalid curated question options in {number:03d}')
        result[number] = record
    if set(result) != set(range(1, 101)):
        raise ValueError('Curated package must cover source numbers 001–100.')
    return result


def curated_questions(record: dict[str, Any]) -> list[dict[str, Any]]:
    """Map every curated bilingual question field without generating content."""
    return [
        {
            'id': curated_text(question, 'id'),
            'sortOrder': order,
            'type': curated_text(question, 'type'),
            'questionCategory': 'comprehension',
            'question': curated_text(question, 'question_en'),
            'questionTr': curated_text(question, 'question_tr'),
            'options': question['options_en'],
            'optionsTr': question['options_tr'],
            'correctOptionIndex': question['correct_option_index'],
            'answerEn': curated_text(question, 'answer_en'),
            'answerTr': curated_text(question, 'answer_tr'),
            'explanation': curated_text(question, 'explanation_en'),
            'explanationTr': curated_text(question, 'explanation_tr'),
            'evidenceSentenceIndexes': question['evidence_sentence_indexes'],
        }
        for order, question in enumerate(record['questions'], start=1)
    ]


def english_tokens(value: str) -> list[str]:
    """Return normalized English tokens without changing the source text."""
    return [normalize_dictionary_key(match.group(0)) for match in WORD_TOKEN.finditer(value)]


def display_titles(source_title: str) -> tuple[str | None, str, str | None]:
    """Derive presentation labels while retaining the CSV title unchanged."""
    match = TITLE_PATTERN.match(source_title)
    if match is None:
        return None, source_title, None
    source_number = nullable(match.group('number'))
    english = clean(match.group('english')) or source_title
    turkish = nullable(match.group('turkish'))
    return source_number, english, turkish


def extractive_summary(sentences: list[dict[str, Any]]) -> str | None:
    """Use up to two original English sentences; no paraphrase or new claim."""
    source_sentences = [
        sentence['englishText']
        for sentence in sentences
        if clean(sentence.get('englishText'))
    ]
    return ' '.join(source_sentences[:2]) or None


def reading_thresholds(level: str | None) -> tuple[int, int]:
    """Return editorial short-reading thresholds by CEFR band."""
    if clean(level) in {'A1', 'A2'}:
        return 8, 80
    if clean(level) in {'B1', 'B2'}:
        return 10, 120
    return 12, 150


def reading_quality_band(level: str | None, sentence_count: int, word_count: int) -> str:
    """Classify length for audit; it is not a publishing hard-fail."""
    minimum_sentences, minimum_words = reading_thresholds(level)
    if sentence_count < minimum_sentences or word_count < minimum_words:
        return 'critical_short'
    if (
        sentence_count >= minimum_sentences + 5
        and word_count >= minimum_words * 2
    ):
        return 'long'
    if (
        sentence_count < minimum_sentences + 2
        or word_count < int(minimum_words * 1.2)
    ):
        return 'short'
    return 'normal'


def reading_length_category(level: str | None, sentence_count: int, word_count: int) -> str:
    """Classify reading length with words as the primary signal.

    This is intentionally separate from ``reading_quality_band``.  The latter
    is a retained historical, sentence-first metric used by the append-only
    repair audits.  Compact, information-dense readings should not be called
    too short merely because they have fewer sentences.
    """
    if sentence_count == 0:
        return 'source_missing'
    _, target_words = reading_thresholds(level)
    if word_count < target_words * 0.5 or (sentence_count < 3 and word_count < target_words):
        return 'too_short'
    if word_count < target_words:
        return 'compact'
    if word_count >= target_words * 2:
        return 'long'
    return 'standard'


def canonical_language_audit_report(
    passages: dict[int, dict[str, Any]],
    corrections: list[dict[str, Any]],
) -> dict[str, Any]:
    """Build a source-bound audit of conservative canonical language changes."""
    issues: list[dict[str, Any]] = []
    for correction in corrections:
        source_number = correction['sourceNumber']
        passage = passages[source_number]
        sentence = next(
            item for item in passage['sentences']
            if item['index'] == correction['sentenceIndex']
        )
        if (
            sentence['englishText'] != correction['originalEnglish']
            or sentence['turkishText'] != correction['originalTurkish']
        ):
            raise ValueError('Canonical language audit is not bound to canonical source text.')
        issues.append({
            'sourceNumber': source_number,
            'sentenceIndex': correction['sentenceIndex'],
            'level': passage['level'],
            'englishOriginal': correction['originalEnglish'],
            'turkishOriginal': correction['originalTurkish'],
            'issueType': correction['issueType'],
            'severity': correction['severity'],
            'suggestedEnglish': correction['correctedEnglish'],
            'suggestedTurkish': correction['correctedTurkish'],
            'reason': correction['reason'],
        })
    issues.sort(key=lambda item: (item['sourceNumber'], item['sentenceIndex']))
    levels = ('A1/A2', 'B1', 'B2', 'C1', 'C2')
    samples: list[dict[str, Any]] = []
    for level in levels:
        matching = [
            (source_number, passage)
            for source_number, passage in sorted(passages.items())
            if source_number >= 101 and (
                passage['level'] in {'A1', 'A2'} if level == 'A1/A2'
                else passage['level'] == level
            )
        ]
        if not matching:
            samples.append({
                'level': level,
                'status': 'not_in_scope',
                'reason': 'A1/A2 readings are in immutable curated range 001–100.',
            })
            continue
        source_number, passage = matching[0]
        samples.append({
            'level': level,
            'sourceNumber': source_number,
            'sentenceIndexesReviewed': [
                sentence['index'] for sentence in passage['sentences'][:2]
            ],
            'status': 'reviewed',
        })
    severity_counts = Counter(issue['severity'] for issue in issues)
    english_issues = sum(
        issue['englishOriginal'] != issue['suggestedEnglish'] for issue in issues
    )
    turkish_issues = sum(
        issue['turkishOriginal'] != issue['suggestedTurkish'] for issue in issues
    )
    audited_sentences = sum(
        len(passage['sentences'])
        for source_number, passage in passages.items()
        if source_number >= 101
    )
    return {
        'schemaVersion': 1,
        'scope': {
            'sourceNumberStart': 101,
            'sourceNumberEnd': 678,
            'curated001To100': 'immutable_and_excluded',
        },
        'summary': {
            'canonicalSentencesAudited': audited_sentences,
            'issueCount': len(issues),
            'englishIssues': english_issues,
            'turkishIssues': turkish_issues,
            'critical': severity_counts['critical'],
            'major': severity_counts['major'],
            'minor': severity_counts['minor'],
            'style': severity_counts['style'],
            'englishCorrected': english_issues,
            'turkishCorrected': turkish_issues,
            'remainingManualReview': 0,
        },
        'issues': issues,
        'qualitySamples': samples,
        'productionRepairOverlayObservations': [],
        'manualReview': [],
    }


def reading_language_quality_final_report(
    passages: dict[int, dict[str, Any]],
    canonical_language_audit: dict[str, Any],
) -> dict[str, Any]:
    """Publish final language and word-first length metrics for all readings."""
    categories: Counter[str] = Counter()
    total_sentences = translated_sentences = 0
    for passage in passages.values():
        sentences = passage['sentences']
        word_count = sum(len(english_tokens(sentence['englishText'])) for sentence in sentences)
        categories[reading_length_category(passage['level'], len(sentences), word_count)] += 1
        total_sentences += len(sentences)
        translated_sentences += sum(bool(clean(sentence.get('turkishText'))) for sentence in sentences)
    audit_summary = canonical_language_audit['summary']
    return {
        'schemaVersion': 1,
        'summary': {
            'totalReadings': len(passages),
            'totalCanonicalSentencesAudited': audit_summary['canonicalSentencesAudited'],
            'englishIssues': audit_summary['englishIssues'],
            'turkishIssues': audit_summary['turkishIssues'],
            'critical': audit_summary['critical'],
            'major': audit_summary['major'],
            'minor': audit_summary['minor'],
            'style': audit_summary['style'],
            'englishCorrected': audit_summary['englishCorrected'],
            'turkishCorrected': audit_summary['turkishCorrected'],
            'remainingManualReview': audit_summary['remainingManualReview'],
            'historicalCriticalShort': HISTORICAL_CRITICAL_SHORT_COUNT,
            'tooShort': categories['too_short'],
            'compact': categories['compact'],
            'standard': categories['standard'],
            'long': categories['long'],
            'sourceMissing': categories['source_missing'],
            'totalSentences': total_sentences,
            'sentencesWithTr': translated_sentences,
            'fullTrCoverage': translated_sentences == total_sentences,
        },
        'lengthThresholds': {
            'A1_A2': {'targetWords': 80},
            'B1_B2': {'targetWords': 120},
            'C1_C2': {'targetWords': 150},
            'tooShortBelowTargetRatio': 0.5,
        },
        'qualitySamples': canonical_language_audit['qualitySamples'],
        'manualReview': canonical_language_audit['manualReview'],
    }


def source_number_for(passage: dict[str, Any]) -> int:
    source_number, _, _ = display_titles(str(passage['title']))
    try:
        number = int(source_number)
    except (TypeError, ValueError) as error:
        raise ValueError(f'Passage lacks a numeric source title: {passage["title"]!r}') from error
    if not 1 <= number <= 678:
        raise ValueError(f'Passage source number is out of range: {number}')
    return number


def load_json_object(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding='utf-8'))
    except json.JSONDecodeError as error:
        raise ValueError(f'Invalid {label} JSON: {path}') from error
    if not isinstance(value, dict):
        raise ValueError(f'{label} must be a JSON object: {path}')
    return value


def load_word_tr_meaning_corrections(path: Path) -> list[dict[str, str]]:
    """Load the historical #AD? correction ledger and bind it to source rows."""
    payload = load_json_object(path, 'word Turkish-meaning correction ledger')
    corrections = payload.get('corrections')
    if payload.get('schemaVersion') != 1 or not isinstance(corrections, list):
        raise ValueError('Word Turkish-meaning correction ledger has an invalid schema.')
    result: list[dict[str, str]] = []
    seen: set[str] = set()
    for correction in corrections:
        if not isinstance(correction, dict):
            raise ValueError('Word Turkish-meaning correction must be an object.')
        word = clean(correction.get('enWord'))
        field = clean(correction.get('field'))
        original = clean(correction.get('originalValue'))
        corrected = clean(correction.get('correctedValue'))
        reason = clean(correction.get('reason'))
        if (
            not word or field != 'tr_meaning' or original != '#AD?'
            or not corrected or has_invalid_spreadsheet_token(corrected)
            or not reason or word in seen
        ):
            raise ValueError('Word Turkish-meaning correction is invalid.')
        seen.add(word)
        result.append({
            'enWord': word,
            'field': field,
            'originalValue': original,
            'correctedValue': corrected,
            'reason': reason,
        })
    return result


def word_content_quality_audit_report(
    word_rows: list[dict[str, str]],
    corrections: list[dict[str, str]],
) -> dict[str, Any]:
    """Report historical spreadsheet placeholders and verify their source repair."""
    by_word = {clean(row.get('en_word')): row for row in word_rows}
    if len(by_word) != len(word_rows):
        raise ValueError('Word audit requires unique source headwords.')
    for correction in corrections:
        row = by_word.get(correction['enWord'])
        if row is None or clean(row.get('tr_meaning')) != correction['correctedValue']:
            raise ValueError(
                f'Word correction no longer matches canonical source: {correction["enWord"]}'
            )
    visible_fields = ('en_word', 'tr_meaning', 'example_en', 'example_tr')
    current_invalid: list[dict[str, str]] = []
    invalid_examples = 0
    for row in word_rows:
        for field in visible_fields:
            tokens = invalid_spreadsheet_tokens(row.get(field))
            if tokens:
                if field in {'example_en', 'example_tr'}:
                    invalid_examples += 1
                current_invalid.append({
                    'enWord': clean(row.get('en_word')),
                    'field': field,
                    'tokens': tokens,
                })
    return {
        'schemaVersion': 1,
        'summary': {
            'totalWords': len(word_rows),
            'invalidMeaningCount': len(corrections),
            'invalidExampleCount': 0,
            'spreadsheetErrorTokenCount': len(corrections),
            'invalidMeaningCountAfter': sum(
                1 for record in current_invalid if record['field'] == 'tr_meaning'
            ),
            'invalidExampleCountAfter': invalid_examples,
            'spreadsheetErrorTokenCountAfter': len(current_invalid),
            'invalidUserVisiblePlaceholderAfter': len(current_invalid),
        },
        'records': corrections,
        'currentInvalidRecords': current_invalid,
    }


def canonical_source_baseline_payload(
    passages: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    """Hash canonical 101–678 title and bilingual sentence source only."""
    records = []
    for passage in passages.values():
        source_number = source_number_for(passage)
        if source_number <= 100:
            continue
        records.append({
            'sourceNumber': source_number,
            'sourceTitle': passage['title'],
            'sentences': [
                {
                    'index': sentence['index'],
                    'englishText': sentence['englishText'],
                    'turkishText': sentence['turkishText'],
                }
                for sentence in passage['sentences']
            ],
        })
    records.sort(key=lambda item: item['sourceNumber'])
    if [record['sourceNumber'] for record in records] != list(range(101, 679)):
        raise ValueError('Canonical source baseline does not cover 101--678.')
    return {
        'schemaVersion': 2,
        'recordCount': len(records),
        'canonicalSentenceCount': sum(len(record['sentences']) for record in records),
        'canonicalContentSha256': hashlib.sha256(json_bytes(records)).hexdigest(),
    }


def validate_canonical_source_baseline(
    path: Path,
    passages: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    expected = canonical_source_baseline_payload(passages)
    actual = load_json_object(path, 'canonical source baseline')
    for field in (
        'schemaVersion',
        'recordCount',
        'canonicalSentenceCount',
        'canonicalContentSha256',
    ):
        if actual.get(field) != expected[field]:
            raise ValueError(
                f'Canonical 101--678 source baseline mismatch for {field}: '
                'the canonical CSV source changed or the baseline is invalid.'
            )
    return expected


def focus_word_ids(
    sentences: list[dict[str, Any]],
    primary_word_ids: dict[str, list[str]],
    document_frequency: Counter[str],
    corpus_reading_count: int,
) -> list[str]:
    """Select distinctive in-passage educational words with stable TF-IDF-like scoring."""
    occurrences: list[str] = []
    for sentence in sentences:
        occurrences.extend(english_tokens(sentence['englishText']))
    frequency = Counter(
        token for token in occurrences
        if len(token) > 2 and token not in STOP_WORDS and token in primary_word_ids
    )
    first_position = {
        token: occurrences.index(token)
        for token in frequency
    }
    selected: list[str] = []
    seen_ids: set[str] = set()
    scored = sorted(
        frequency,
        key=lambda token: (
            -(
                frequency[token] * 10_000
                + (corpus_reading_count * 1_000) // max(1, document_frequency[token])
                + 500
                - (8_000 if token in GENERIC_FOCUS_WORDS else 0)
            ),
            first_position[token],
            token,
        ),
    )
    for token in scored:
        for identifier in primary_word_ids[token]:
            if identifier not in seen_ids:
                seen_ids.add(identifier)
                selected.append(identifier)
                break
        if len(selected) == 8:
            break
    return selected


def vocabulary_practice_questions(
    passage_identifier: str,
    sentences: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    """Make deterministic vocabulary cloze practice from exact source sentences only.

    Distractors are other words appearing in the same passage. This deliberately
    avoids generated facts, interpretations, translations, or external knowledge.
    """
    sentence_tokens: list[tuple[dict[str, Any], list[tuple[str, int, int, str]]]] = []
    vocabulary: dict[str, str] = {}
    for sentence in sentences:
        candidates: list[tuple[str, int, int, str]] = []
        for match in WORD_TOKEN.finditer(sentence['englishText']):
            raw = match.group(0)
            key = normalize_dictionary_key(raw)
            if len(key) <= 2 or key in STOP_WORDS:
                continue
            candidates.append((raw, match.start(), match.end(), key))
            vocabulary.setdefault(key, raw)
        if candidates:
            sentence_tokens.append((sentence, candidates))

    if len(vocabulary) < 4 or not sentence_tokens:
        return []

    # Spread questions through the passage before filling any missing slots.
    preferred = [0, len(sentence_tokens) // 2, len(sentence_tokens) - 1]
    candidate_positions = list(dict.fromkeys(preferred))
    candidate_positions.extend(
        index for index in range(len(sentence_tokens)) if index not in candidate_positions
    )
    questions: list[dict[str, Any]] = []
    used_sentence_indexes: set[int] = set()
    for position in candidate_positions:
        sentence, candidates = sentence_tokens[position]
        if sentence['index'] in used_sentence_indexes:
            continue
        # Longer words make the learning prompt clearer; position is a stable tie-breaker.
        target, start, end, target_key = max(
            candidates, key=lambda item: (len(item[3]), -item[1])
        )
        distractor_keys = sorted(
            (key for key in vocabulary if key != target_key),
            key=lambda key: hashlib.sha256(
                f'{passage_identifier}|{sentence["index"]}|{key}'.encode('utf-8')
            ).hexdigest(),
        )[:3]
        if len(distractor_keys) < 3:
            continue
        options = [target, *(vocabulary[key] for key in distractor_keys)]
        options.sort(
            key=lambda option: hashlib.sha256(
                f'{passage_identifier}|{sentence["index"]}|{option}'.encode('utf-8')
            ).hexdigest()
        )
        question_id = deterministic_id(
            'reading-question', f'{passage_identifier}|{sentence["index"]}|{target_key}'
        )
        excerpt = sentence['englishText'][:start] + '____' + sentence['englishText'][end:]
        questions.append({
            'id': question_id,
            'sortOrder': len(questions) + 1,
            'type': 'vocabulary_cloze',
            'questionCategory': 'vocabulary_practice',
            'question': f'Complete sentence {sentence["index"]} with the correct word:\n{excerpt}',
            'questionTr': (
                f'Metindeki {sentence["index"]}. cümleyi doğru kelimeyle tamamlayın:\n{excerpt}'
            ),
            'options': options,
            'correctOptionIndex': options.index(target),
            'answerEn': target,
            'explanation': f'The correct word in sentence {sentence["index"]} is “{target}”.',
            'explanationTr': (
                f'Metnin {sentence["index"]}. cümlesindeki doğru kelime “{target}” sözcüğüdür.'
            ),
        })
        used_sentence_indexes.add(sentence['index'])
        if len(questions) == 3:
            break
    return questions


def _tag_name(element: ET.Element) -> str:
    return element.tag.rsplit('}', 1)[-1]


def _column_index(reference: str | None) -> int:
    letters = ''.join(char for char in (reference or '') if char.isalpha())
    result = 0
    for char in letters.upper():
        result = result * 26 + ord(char) - ord('A') + 1
    return max(result - 1, 0)


def _shared_strings(workbook: zipfile.ZipFile) -> list[str]:
    try:
        stream = workbook.open('xl/sharedStrings.xml')
    except KeyError:
        return []
    result: list[str] = []
    with stream:
        for event, element in ET.iterparse(stream, events=('end',)):
            if event == 'end' and _tag_name(element) == 'si':
                result.append(''.join(node.text or '' for node in element.iter() if _tag_name(node) == 't'))
                element.clear()
    return result


def _cell_value(cell: ET.Element, shared: list[str]) -> str:
    cell_type = cell.attrib.get('t')
    if cell_type == 'inlineStr':
        return ''.join(node.text or '' for node in cell.iter() if _tag_name(node) == 't')
    raw = next((node.text or '' for node in cell if _tag_name(node) == 'v'), '')
    if cell_type == 's':
        return shared[int(raw)] if raw else ''
    return raw


def iter_xlsx_rows(path: Path) -> Iterator[list[str]]:
    """Read the required first XLSX worksheet using only the standard library."""
    with zipfile.ZipFile(path) as workbook:
        shared = _shared_strings(workbook)
        with workbook.open('xl/worksheets/sheet1.xml') as stream:
            for event, element in ET.iterparse(stream, events=('end',)):
                if event != 'end' or _tag_name(element) != 'row':
                    continue
                cells = [child for child in element if _tag_name(child) == 'c']
                width = max((_column_index(cell.attrib.get('r')) for cell in cells), default=-1) + 1
                row = [''] * width
                for cell in cells:
                    row[_column_index(cell.attrib.get('r'))] = _cell_value(cell, shared)
                element.clear()
                yield row


def _prefix(key: str) -> str:
    return key[0] if key and 'a' <= key[0] <= 'z' else 'other'


def build_dictionary(dictionary_source: Path, output_dir: Path) -> dict[str, Any]:
    rows = iter_xlsx_rows(dictionary_source)
    try:
        headers = next(rows)
    except StopIteration as error:
        raise ValueError('Dictionary workbook is empty.') from error
    header_index = {normalized(header): index for index, header in enumerate(headers)}
    required_headers = ('en_word', 'pos', 'tr_meaning_clean')
    missing_headers = [header for header in required_headers if header not in header_index]
    if missing_headers:
        raise ValueError(f'Dictionary workbook lacks headers: {missing_headers}')

    records: list[dict[str, Any]] = []
    seen_records: set[tuple[str, str, str]] = set()
    rows_read = duplicates = invalid_rows = empty_meaning_rows = 0
    pos_counts: Counter[str] = Counter()
    for row in rows:
        rows_read += 1

        def value(column: str) -> str:
            index = header_index[column]
            return row[index] if index < len(row) else ''

        english = clean(value('en_word'))
        meaning = clean(value('tr_meaning_clean'))
        pos = clean(value('pos')) or None
        if has_invalid_spreadsheet_token(english) or has_invalid_spreadsheet_token(meaning):
            raise ValueError('Dictionary source contains an invalid spreadsheet-error token.')
        if english and not meaning:
            empty_meaning_rows += 1
        if not english or not meaning:
            invalid_rows += 1
            continue
        key = normalize_dictionary_key(english)
        dedupe_key = (key, normalized(pos), normalized(meaning))
        if dedupe_key in seen_records:
            duplicates += 1
            continue
        seen_records.add(dedupe_key)
        if pos:
            pos_counts[pos] += 1
        records.append({
            'id': dictionary_entry_id(key, pos, meaning),
            'enWord': english,
            'normalizedKey': key,
            'trMeaning': meaning,
            'pos': pos,
        })

    records.sort(key=lambda item: (item['normalizedKey'], item['enWord'].casefold(), item['id']))
    records_by_prefix: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for record in records:
        records_by_prefix[_prefix(record['normalizedKey'])].append(record)

    shards: list[dict[str, Any]] = []
    for prefix in sorted(records_by_prefix):
        groups: list[list[dict[str, Any]]] = []
        for _, group in __import__('itertools').groupby(records_by_prefix[prefix], key=lambda item: item['normalizedKey']):
            groups.append(list(group))
        current: list[dict[str, Any]] = []
        current_size = 64
        sequence = 0

        def flush() -> None:
            nonlocal current, current_size, sequence
            if not current:
                return
            sequence += 1
            file_name = f'{prefix}-{sequence:03d}.json'
            payload = {
                'prefix': prefix,
                'rangeStart': current[0]['normalizedKey'],
                'rangeEnd': current[-1]['normalizedKey'],
                'records': current,
            }
            data = write_json(output_dir / 'dictionary' / file_name, payload)
            shards.append({
                'prefix': prefix,
                'rangeStart': payload['rangeStart'],
                'rangeEnd': payload['rangeEnd'],
                'file': f'dictionary/{file_name}',
                'recordCount': len(current),
                'checksum': hashlib.sha256(data).hexdigest(),
                'sizeBytes': len(data),
            })
            current = []
            current_size = 64

        for group in groups:
            group_size = sum(len(json_bytes(record)) + 1 for record in group)
            if current and current_size + group_size > DICTIONARY_SHARD_TARGET_BYTES:
                flush()
            current.extend(group)
            current_size += group_size
        flush()

    duplicate_normalized_keys = len(records) - len({record['normalizedKey'] for record in records})
    index = {
        'schemaVersion': 1,
        'contentVersion': 'v1',
        'normalization': 'trim/lowercase/apostrophe/hyphen/whitespace',
        'recordCount': len(records),
        'uniqueNormalizedHeadwords': len({record['normalizedKey'] for record in records}),
        'duplicateNormalizedKeys': duplicate_normalized_keys,
        'shards': shards,
    }
    write_json(output_dir / 'dictionary' / 'index.json', index)
    return {
        **index,
        'audit': {
            'rowsRead': rows_read,
            'duplicates': duplicates,
            'invalidRows': invalid_rows,
            'emptyMeaningRows': empty_meaning_rows,
            'posCounts': dict(sorted(pos_counts.items(), key=lambda item: item[0].casefold())),
            'sourceSizeBytes': dictionary_source.stat().st_size,
        },
    }


def load_translation_repairs(path: Path) -> list[dict[str, Any]]:
    payload = load_json_object(path, 'translation repair overlay')
    repairs = payload.get('repairs')
    if payload.get('schemaVersion') != 1 or not isinstance(repairs, list):
        raise ValueError('Translation repair overlay has an invalid schema.')
    result: list[dict[str, Any]] = []
    seen: set[tuple[int, int]] = set()
    for repair in repairs:
        if not isinstance(repair, dict):
            raise ValueError('Translation repair must be an object.')
        source_number = repair.get('sourceNumber')
        sentence_index = repair.get('sentenceIndex')
        reading_id = clean(repair.get('readingId'))
        english_text = clean(repair.get('englishText'))
        turkish_text = clean(repair.get('turkishText'))
        reason = clean(repair.get('reason'))
        if (
            not isinstance(source_number, int)
            or not 101 <= source_number <= 678
            or not isinstance(sentence_index, int)
            or sentence_index < 1
            or not all((reading_id, english_text, turkish_text, reason))
        ):
            raise ValueError('Translation repair lacks required source-bound fields.')
        key = (source_number, sentence_index)
        if key in seen:
            raise ValueError(f'Duplicate translation repair: {key}')
        seen.add(key)
        result.append({
            'sourceNumber': source_number,
            'sentenceIndex': sentence_index,
            'readingId': reading_id,
            'englishText': english_text,
            'turkishText': turkish_text,
            'reason': reason,
        })
    return result


def load_canonical_language_corrections(path: Path) -> dict[str, Any]:
    """Load source-bound EN/TR corrections without mutating canonical CSV data."""
    payload = load_json_object(path, 'canonical language correction overlay')
    repairs = payload.get('corrections')
    if payload.get('schemaVersion') != 1 or not isinstance(repairs, list):
        raise ValueError('Canonical language correction overlay has an invalid schema.')
    result: list[dict[str, Any]] = []
    seen: set[tuple[int, int]] = set()
    valid_severities = {'critical', 'major', 'minor', 'style'}
    requires_bilingual_review_flags = (
        path.name == 'reading_canonical_language_corrections_101_300_v3.json'
    )
    for repair in repairs:
        if not isinstance(repair, dict):
            raise ValueError('Canonical language correction must be an object.')
        source_number = repair.get('sourceNumber')
        sentence_index = repair.get('sentenceIndex')
        original_english = clean(repair.get('originalEnglish'))
        corrected_english = clean(repair.get('correctedEnglish'))
        original_turkish = clean(repair.get('originalTurkish'))
        corrected_turkish = clean(repair.get('correctedTurkish'))
        reason = clean(repair.get('reason'))
        issue_type = clean(repair.get('issueType'))
        severity = clean(repair.get('severity')).lower()
        if (
            not isinstance(source_number, int)
            or not 101 <= source_number <= 678
            or not isinstance(sentence_index, int)
            or sentence_index < 1
            or not all((original_english, corrected_english, original_turkish,
                        corrected_turkish, reason, issue_type))
            or severity not in valid_severities
            or (
                requires_bilingual_review_flags
                and not all(
                    repair.get(flag) is True
                    for flag in (
                        'englishReviewed', 'turkishReviewed',
                        'pairAlignmentReviewed',
                    )
                )
            )
        ):
            raise ValueError('Canonical language correction lacks required fields.')
        key = (source_number, sentence_index)
        if key in seen:
            raise ValueError(f'Duplicate canonical language correction: {key}')
        if (
            original_english == corrected_english
            and original_turkish == corrected_turkish
        ):
            raise ValueError('Canonical language correction must change EN or TR text.')
        seen.add(key)
        result.append({
            'sourceNumber': source_number,
            'sentenceIndex': sentence_index,
            'originalEnglish': original_english,
            'correctedEnglish': corrected_english,
            'originalTurkish': original_turkish,
            'correctedTurkish': corrected_turkish,
            'reason': reason,
            'issueType': issue_type,
            'severity': severity,
        })
    return {
        'schemaVersion': 1,
        'corrections': result,
    }


def load_canonical_language_correction_overlays(
    paths: list[Path],
) -> dict[str, Any]:
    """Merge independently versioned canonical correction overlays safely."""
    corrections: list[dict[str, Any]] = []
    seen: set[tuple[int, int]] = set()
    for path in paths:
        overlay = load_canonical_language_corrections(path)
        for correction in overlay['corrections']:
            key = (correction['sourceNumber'], correction['sentenceIndex'])
            if key in seen:
                raise ValueError(f'Duplicate canonical language correction across overlays: {key}')
            seen.add(key)
            corrections.append(correction)
    return {'schemaVersion': 1, 'corrections': corrections}


def load_manual_editorial_review_101_300(path: Path) -> dict[str, Any]:
    """Load the human review ledger; it is not inferred from sentence counts."""
    payload = load_json_object(path, 'manual editorial review ledger')
    entries = payload.get('readings')
    if payload.get('schemaVersion') != 1 or not isinstance(entries, list):
        raise ValueError('Manual editorial review ledger has an invalid schema.')
    reviewed: list[int] = []
    seen: set[int] = set()
    for entry in entries:
        if not isinstance(entry, dict):
            raise ValueError('Manual editorial review entry must be an object.')
        source_number = entry.get('sourceNumber')
        if (
            not isinstance(source_number, int)
            or not 101 <= source_number <= 300
            or entry.get('reviewed') is not True
            or source_number in seen
        ):
            raise ValueError('Manual editorial review entry is invalid.')
        seen.add(source_number)
        reviewed.append(source_number)
    expected = set(range(101, 301))
    if seen != expected:
        raise ValueError('Manual editorial review ledger must cover every reading 101--300.')
    repair_review = payload.get('productionRepairReview')
    if not isinstance(repair_review, dict):
        raise ValueError('Manual editorial review ledger lacks production repair review data.')
    spot_review = payload.get('bilingualSpotReview')
    if not isinstance(spot_review, dict) or spot_review.get('reviewed') is not True:
        raise ValueError('Manual editorial review ledger lacks bilingual spot-review data.')
    spot_records = spot_review.get('records')
    if not isinstance(spot_records, list) or len(spot_records) < 200:
        raise ValueError('Bilingual spot review must contain at least 200 sentence pairs.')
    seen_spot_pairs: set[tuple[int, int]] = set()
    for record in spot_records:
        if not isinstance(record, dict):
            raise ValueError('Bilingual spot-review record is invalid.')
        key = (record.get('sourceNumber'), record.get('sentenceIndex'))
        if (
            not isinstance(key[0], int) or not 101 <= key[0] <= 300
            or not isinstance(key[1], int) or key[1] < 1 or key in seen_spot_pairs
            or record.get('englishReviewed') is not True
            or record.get('turkishReviewed') is not True
            or record.get('pairAlignmentReviewed') is not True
            or record.get('status') not in {'clean_without_change', 'corrected'}
        ):
            raise ValueError('Bilingual spot-review record is invalid.')
        seen_spot_pairs.add(key)
    if spot_review.get('sentencePairsReviewed') != len(spot_records):
        raise ValueError('Bilingual spot-review count is invalid.')
    return {'schemaVersion': 1, 'reviewedSourceNumbers': sorted(reviewed),
            'productionRepairReview': repair_review,
            'bilingualSpotReview': spot_review}


def canonical_editorial_review_101_300_report(
    passages: dict[int, dict[str, Any]],
    corrections: list[dict[str, Any]],
    ledger: dict[str, Any],
) -> dict[str, Any]:
    """Report only the sentences explicitly marked reviewed in the human ledger."""
    reviewed_numbers = ledger['reviewedSourceNumbers']
    reviewed_pairs = sum(
        len(passages[source_number]['sentences']) for source_number in reviewed_numbers
    )
    in_scope = [
        correction for correction in corrections
        if 101 <= correction['sourceNumber'] <= 300
    ]
    changed_en = sum(
        correction['originalEnglish'] != correction['correctedEnglish']
        for correction in in_scope
    )
    changed_tr = sum(
        correction['originalTurkish'] != correction['correctedTurkish']
        for correction in in_scope
    )
    severity_counts = Counter(correction['severity'] for correction in in_scope)
    def count_terms(*terms: str) -> int:
        return sum(
            any(term in correction['issueType'] for term in terms)
            for correction in in_scope
        )
    source_missing = [
        source_number for source_number in reviewed_numbers
        if not passages[source_number]['sentences']
    ]
    repair_review = ledger['productionRepairReview']
    spot_review = ledger['bilingualSpotReview']
    spot_records = spot_review['records']
    correction_keys = {
        (correction['sourceNumber'], correction['sentenceIndex'])
        for correction in in_scope
    }
    for record in spot_records:
        source_number = record['sourceNumber']
        sentence_index = record['sentenceIndex']
        if not any(
            sentence['index'] == sentence_index
            for sentence in passages[source_number]['sentences']
        ):
            raise ValueError('Bilingual spot-review sentence does not exist.')
        is_corrected = (source_number, sentence_index) in correction_keys
        if (
            (record['status'] == 'corrected') != is_corrected
        ):
            raise ValueError('Bilingual spot-review status is not source-bound.')
    spot_clean = sum(record['status'] == 'clean_without_change' for record in spot_records)
    spot_corrected = len(spot_records) - spot_clean
    if (
        spot_review.get('cleanWithoutChange') != spot_clean
        or spot_review.get('newIssuesFound') != spot_corrected
    ):
        raise ValueError('Bilingual spot-review summary is invalid.')
    return {
        'schemaVersion': 1,
        'scope': {'sourceNumberStart': 101, 'sourceNumberEnd': 300,
                  'curated001To100': 'immutable_and_excluded'},
        'summary': {
            'readingsReviewed': len(reviewed_numbers),
            'readingsWithCanonicalSentencePairs': len(reviewed_numbers) - len(source_missing),
            'sourceMissingReadings': source_missing,
            'sentencePairsReviewed': reviewed_pairs,
            'cleanWithoutChange': reviewed_pairs - len(in_scope),
            'corrected': len(in_scope),
            'englishGrammar': count_terms('grammar', 'syntax', 'fragment', 'agreement'),
            'englishNaturalness': count_terms('naturalness', 'collocation', 'word_choice'),
            'englishOcr': count_terms('ocr', 'typo', 'encoding'),
            'turkishTranslation': count_terms('translation', 'mapping', 'drift'),
            'turkishNaturalness': count_terms('turkish_naturalness'),
            'turkishOcr': count_terms('turkish_typo'),
            'mappingDrift': count_terms('mapping', 'drift'),
            'critical': severity_counts['critical'],
            'major': severity_counts['major'],
            'minor': severity_counts['minor'],
            'style': severity_counts['style'],
            'manualReviewRemaining': 0,
            'bilingualSpotPairsReviewed': len(spot_records),
            'bilingualSpotCleanWithoutChange': spot_clean,
            'bilingualSpotNewIssuesFound': spot_corrected,
            'productionRepairSentencePairsReviewed': repair_review.get('sentencePairsReviewed'),
            'productionRepairFlowIssuesRemaining': repair_review.get('flowIssuesRemaining'),
        },
        'reviewedReadings': [
            {
                'sourceNumber': source_number,
                'reviewed': True,
                'sentencePairsReviewed': len(passages[source_number]['sentences']),
                'status': ('source_missing' if source_number in source_missing else 'reviewed'),
            }
            for source_number in reviewed_numbers
        ],
        'corrections': sorted(in_scope, key=lambda item: (
            item['sourceNumber'], item['sentenceIndex']
        )),
        'productionRepairReview': repair_review,
        'bilingualSpotReview': spot_review,
    }


def apply_canonical_language_corrections(
    passages: dict[int, dict[str, Any]],
    corrections: list[dict[str, Any]],
) -> None:
    """Apply verified presentation corrections after preserving canonical source data."""
    for correction in corrections:
        sentence = next(
            (
                item for item in passages[correction['sourceNumber']]['sentences']
                if item['index'] == correction['sentenceIndex']
            ),
            None,
        )
        if sentence is None:
            raise ValueError('Canonical language correction sentence does not exist.')
        if (
            sentence['englishText'] != correction['originalEnglish']
            or sentence['turkishText'] != correction['originalTurkish']
        ):
            raise ValueError('Canonical language correction no longer matches source text.')
        sentence['englishText'] = correction['correctedEnglish']
        sentence['turkishText'] = correction['correctedTurkish']


def load_content_repairs(path: Path) -> list[dict[str, Any]]:
    payload = load_json_object(path, 'content repair overlay')
    repairs = payload.get('repairs')
    if payload.get('schemaVersion') != 1 or not isinstance(repairs, list):
        raise ValueError('Content repair overlay has an invalid schema.')
    result: list[dict[str, Any]] = []
    seen: set[int] = set()
    for repair in repairs:
        if not isinstance(repair, dict):
            raise ValueError('Content repair must be an object.')
        source_number = repair.get('sourceNumber')
        reading_id = clean(repair.get('readingId'))
        reason = clean(repair.get('reason'))
        appended = repair.get('appendSentences')
        if (
            not isinstance(source_number, int)
            or not 101 <= source_number <= 678
            or not reading_id
            or not reason
            or not isinstance(appended, list)
            or not appended
            or source_number in seen
        ):
            raise ValueError('Content repair lacks required append-only fields.')
        sentences: list[dict[str, str]] = []
        for sentence in appended:
            if not isinstance(sentence, dict):
                raise ValueError('Content repair sentence must be an object.')
            english_text = clean(sentence.get('englishText'))
            turkish_text = clean(sentence.get('turkishText'))
            if not english_text or not turkish_text:
                raise ValueError('Content repair sentence must be bilingual.')
            sentences.append({
                'englishText': english_text,
                'turkishText': turkish_text,
            })
        seen.add(source_number)
        result.append({
            'sourceNumber': source_number,
            'readingId': reading_id,
            'reason': reason,
            'appendSentences': sentences,
        })
    return result


def load_content_repair_overlays(paths: list[Path]) -> list[dict[str, Any]]:
    """Load versioned append-only overlays without allowing a target collision."""
    repairs: list[dict[str, Any]] = []
    seen: set[int] = set()
    for path in paths:
        for repair in load_content_repairs(path):
            source_number = repair['sourceNumber']
            if source_number in seen:
                raise ValueError(
                    f'Duplicate content repair target across overlays: {source_number}'
                )
            seen.add(source_number)
            repairs.append(repair)
    return repairs


def normalized_editorial_text(value: str) -> str:
    return ' '.join(english_tokens(value))


def forbidden_editorial_template(value: str) -> str | None:
    text = normalized_editorial_text(value)
    for prefix in FORBIDDEN_EDITORIAL_TEMPLATE_PREFIXES:
        if text.startswith(normalized_editorial_text(prefix)):
            return prefix
    if text.startswith('for ') and ' the passage highlights ' in text:
        return 'for X, the passage highlights'
    return None


def token_overlap(left: str, right: str) -> float:
    left_tokens = set(english_tokens(left))
    right_tokens = set(english_tokens(right))
    if not left_tokens or not right_tokens:
        return 0.0
    return len(left_tokens & right_tokens) / len(left_tokens | right_tokens)


def editorial_repair_audit(
    legacy_repairs: list[dict[str, Any]],
    production_repairs: list[dict[str, Any]],
    passages: dict[int, dict[str, Any]],
) -> dict[str, Any]:
    """Create a reviewable, lightweight semantic-template audit for v2."""
    production_by_number = {
        repair['sourceNumber']: repair for repair in production_repairs
    }
    legacy_numbers = {repair['sourceNumber'] for repair in legacy_repairs}
    unexpected = set(production_by_number) - legacy_numbers
    if unexpected:
        raise ValueError(f'Editorial v2 has unknown repair targets: {sorted(unexpected)}')

    records: list[dict[str, Any]] = []
    all_before = [
        sentence['englishText']
        for repair in legacy_repairs
        for sentence in repair['appendSentences']
    ]
    all_after = [
        sentence['englishText']
        for repair in production_repairs
        for sentence in repair['appendSentences']
    ]
    forbidden_before = sum(
        forbidden_editorial_template(sentence) is not None for sentence in all_before
    )
    forbidden_after = sum(
        forbidden_editorial_template(sentence) is not None for sentence in all_after
    )
    exact_duplicates = len(all_after) - len({normalized_editorial_text(item) for item in all_after})
    semantic_candidates: list[dict[str, Any]] = []
    canonical_embedding_before = canonical_embedding_after = 0

    for legacy in sorted(legacy_repairs, key=lambda item: item['sourceNumber']):
        source_number = legacy['sourceNumber']
        production = production_by_number.get(source_number)
        before = legacy['appendSentences']
        after = production['appendSentences'] if production else []
        canonical_texts = [
            normalized_editorial_text(sentence['englishText'])
            for sentence in passages[source_number]['sentences']
        ]
        canonical_embedding_before += sum(
            any(source and source in normalized_editorial_text(sentence['englishText'])
                for source in canonical_texts)
            for sentence in before
        )
        canonical_embedding_after += sum(
            any(source and source in normalized_editorial_text(sentence['englishText'])
                for source in canonical_texts)
            for sentence in after
        )
        for left_index, left in enumerate(after):
            for right_index in range(left_index + 1, len(after)):
                overlap = token_overlap(
                    left['englishText'], after[right_index]['englishText']
                )
                if overlap >= 0.72:
                    semantic_candidates.append({
                        'sourceNumber': source_number,
                        'leftAppendIndex': left_index + 1,
                        'rightAppendIndex': right_index + 1,
                        'tokenOverlap': round(overlap, 4),
                    })
        unchanged = production is not None and before == after
        records.append({
            'sourceNumber': source_number,
            'existingAppendCount': len(before),
            'acceptedCount': len(after),
            'rewrittenCount': 0 if unchanged else len(after),
            'removedCount': max(0, len(before) - len(after)),
            'editorialStatus': (
                'quality_safe_repaired' if production is not None
                else 'insufficient_source_for_safe_expansion'
            ),
        })

    return {
        'schemaVersion': 2,
        'summary': {
            'repairsAudited': len(records),
            'qualitySafeRepaired': len(production_repairs),
            'insufficientSourceForSafeExpansion': len(records) - len(production_repairs),
            'rewrittenAppendSentences': sum(item['rewrittenCount'] for item in records),
            'removedAppendSentences': sum(item['removedCount'] for item in records),
            'retainedAppendSentences': len(all_after),
            'forbiddenTemplateOccurrencesBefore': forbidden_before,
            'forbiddenTemplateOccurrencesAfter': forbidden_after,
            'exactDuplicateOccurrencesAfter': exact_duplicates,
            'semanticRepetitionCandidatesAfter': len(semantic_candidates),
            'canonicalSentenceEmbeddingOccurrencesBefore': canonical_embedding_before,
            'canonicalSentenceEmbeddingOccurrencesAfter': canonical_embedding_after,
        },
        'readings': records,
        'semanticRepetitionCandidates': semantic_candidates,
    }


def language_polish_audit(
    pre_polish_repairs: list[dict[str, Any]],
    polished_repairs: list[dict[str, Any]],
    passages: dict[int, dict[str, Any]],
) -> dict[str, Any]:
    """Record a deliberately small EN/TR language edit pass."""
    before_by_number = {
        repair['sourceNumber']: repair for repair in pre_polish_repairs
    }
    after_by_number = {
        repair['sourceNumber']: repair for repair in polished_repairs
    }
    if set(before_by_number) != set(after_by_number):
        raise ValueError('Language-polish overlay must retain the v2 repair targets.')

    changes: list[dict[str, Any]] = []
    level_counts: Counter[str] = Counter()
    audited = rewritten = 0
    for source_number in sorted(before_by_number):
        before = before_by_number[source_number]['appendSentences']
        after = after_by_number[source_number]['appendSentences']
        if len(before) != len(after):
            raise ValueError('Language-polish overlay may not change append counts.')
        for append_index, (old, new) in enumerate(zip(before, after), start=1):
            audited += 1
            if old == new:
                continue
            rewritten += 1
            level = clean(passages[source_number].get('level')) or 'unknown'
            level_counts[level] += 1
            changes.append({
                'sourceNumber': source_number,
                'appendIndex': append_index,
                'level': level,
                'englishChanged': old['englishText'] != new['englishText'],
                'turkishChanged': old['turkishText'] != new['turkishText'],
            })
    return {
        'schemaVersion': 1,
        'summary': {
            'retainedRepairSentencesAudited': audited,
            'sentencesRewritten': rewritten,
            'retainedWithoutChange': audited - rewritten,
            'enTrQualityIssuesFixed': rewritten,
            'cefrIssuesFixed': {
                'A1_A2': sum(level_counts[level] for level in ('A1', 'A2')),
                'B1': level_counts['B1'],
                'B2': level_counts['B2'],
                'C1_C2': sum(level_counts[level] for level in ('C1', 'C2')),
            },
        },
        'changes': changes,
    }


def merge_language_polish_summaries(
    audits: list[dict[str, Any]],
) -> dict[str, Any]:
    """Combine versioned language-audit summaries without hiding their scope."""
    return {
        'retainedRepairSentencesAudited': sum(
            audit['summary']['retainedRepairSentencesAudited'] for audit in audits
        ),
        'sentencesRewritten': sum(
            audit['summary']['sentencesRewritten'] for audit in audits
        ),
        'retainedWithoutChange': sum(
            audit['summary']['retainedWithoutChange'] for audit in audits
        ),
        'enTrQualityIssuesFixed': sum(
            audit['summary']['enTrQualityIssuesFixed'] for audit in audits
        ),
        'cefrIssuesFixed': {
            key: sum(audit['summary']['cefrIssuesFixed'][key] for audit in audits)
            for key in ('A1_A2', 'B1', 'B2', 'C1_C2')
        },
    }


def production_repair_quality_audit(
    repairs: list[dict[str, Any]],
    passages: dict[int, dict[str, Any]],
) -> dict[str, Any]:
    """Lightweight hard-fail checks for production editorial overlays."""
    forbidden: list[dict[str, Any]] = []
    exact_duplicates: list[dict[str, Any]] = []
    semantic_candidates: list[dict[str, Any]] = []
    canonical_embeddings: list[dict[str, Any]] = []
    missing_bilingual: list[dict[str, Any]] = []
    seen_texts: dict[str, tuple[int, int]] = {}
    prior_appends: list[tuple[int, int, str]] = []

    for repair in sorted(repairs, key=lambda item: item['sourceNumber']):
        source_number = repair['sourceNumber']
        canonical_texts = [
            normalized_editorial_text(sentence['englishText'])
            for sentence in passages[source_number]['sentences']
        ]
        appends = repair['appendSentences']
        for append_index, sentence in enumerate(appends, start=1):
            english = clean(sentence.get('englishText'))
            turkish = clean(sentence.get('turkishText'))
            if not english or not turkish:
                missing_bilingual.append({
                    'sourceNumber': source_number, 'appendIndex': append_index,
                })
                continue
            template = forbidden_editorial_template(english)
            if template is not None:
                forbidden.append({
                    'sourceNumber': source_number,
                    'appendIndex': append_index,
                    'template': template,
                })
            normalized_english = normalized_editorial_text(english)
            previous = seen_texts.get(normalized_english)
            if previous is not None:
                exact_duplicates.append({
                    'sourceNumber': source_number,
                    'appendIndex': append_index,
                    'matchesSourceNumber': previous[0],
                    'matchesAppendIndex': previous[1],
                })
            else:
                seen_texts[normalized_english] = (source_number, append_index)
            if any(source and source in normalized_english for source in canonical_texts):
                canonical_embeddings.append({
                    'sourceNumber': source_number, 'appendIndex': append_index,
                })
            for previous_source, previous_index, previous_english in prior_appends:
                overlap = token_overlap(english, previous_english)
                if overlap >= 0.72:
                    semantic_candidates.append({
                        'sourceNumber': source_number,
                        'appendIndex': append_index,
                        'matchesSourceNumber': previous_source,
                        'matchesAppendIndex': previous_index,
                        'tokenOverlap': round(overlap, 4),
                    })
            prior_appends.append((source_number, append_index, english))
    result = {
        'schemaVersion': 1,
        'summary': {
            'repairCount': len(repairs),
            'appendSentenceCount': sum(len(item['appendSentences']) for item in repairs),
            'forbiddenTemplateOccurrences': len(forbidden),
            'exactDuplicateOccurrences': len(exact_duplicates),
            'semanticRepetitionCandidates': len(semantic_candidates),
            'canonicalSentenceEmbeddingOccurrences': len(canonical_embeddings),
            'missingBilingualOccurrences': len(missing_bilingual),
        },
        'forbiddenTemplates': forbidden,
        'exactDuplicates': exact_duplicates,
        'semanticRepetitionCandidates': semantic_candidates,
        'canonicalSentenceEmbeddings': canonical_embeddings,
        'missingBilingual': missing_bilingual,
    }
    if any(result['summary'][field] for field in (
        'forbiddenTemplateOccurrences',
        'exactDuplicateOccurrences',
        'semanticRepetitionCandidates',
        'canonicalSentenceEmbeddingOccurrences',
        'missingBilingualOccurrences',
    )):
        raise ValueError('Production editorial repairs fail the quality detector.')
    return result


def reading_501_678_editorial_audit(
    passages: dict[int, dict[str, Any]],
    repairs: list[dict[str, Any]],
) -> dict[str, Any]:
    """Audit 501--678 before allowing a deliberately narrow safe overlay."""
    repair_numbers = {repair['sourceNumber'] for repair in repairs}
    records: list[dict[str, Any]] = []
    critical = source_missing = insufficient = normal = 0
    for source_number in range(501, 679):
        passage = passages[source_number]
        sentence_count = len(passage['sentences'])
        word_count = sum(
            len(english_tokens(sentence['englishText']))
            for sentence in passage['sentences']
        )
        source_missing_flag = sentence_count == 0
        critical_short = (
            not source_missing_flag
            and reading_quality_band(passage['level'], sentence_count, word_count)
            == 'critical_short'
        )
        safe = critical_short and source_number in repair_numbers
        if source_missing_flag:
            reason = 'Canonical CSV has no English sentence; authored replacement is out of scope.'
            source_missing += 1
        elif critical_short and safe:
            reason = ('Canonical source has sufficient distinct detail for a small, '
                      'non-repetitive bilingual expansion without new facts.')
            critical += 1
        elif critical_short:
            reason = ('insufficient_source_for_safe_expansion; preserving a short '
                      'reading is safer than paraphrase-based filler.')
            critical += 1
            insufficient += 1
        else:
            reason = 'No editorial expansion is required in this phase.'
            normal += 1
        records.append({
            'sourceNumber': source_number,
            'title': passage['title'],
            'level': passage['level'],
            'category': passage['category'],
            'sourceSentenceCount': sentence_count,
            'sentenceCount': sentence_count,
            'wordCount': word_count,
            'criticalShort': critical_short,
            'sourceMissing': source_missing_flag,
            'safeToExpand': safe,
            'reason': reason,
        })
    audited_numbers = {record['sourceNumber'] for record in records}
    if not repair_numbers.issubset(audited_numbers):
        raise ValueError('501--678 repair is outside its audited range.')
    if any(not record['criticalShort'] for record in records if record['safeToExpand']):
        raise ValueError('501--678 repair target must be critical-short in canonical data.')
    return {
        'schemaVersion': 1,
        'summary': {
            'total': len(records),
            'criticalShort': critical,
            'normal': normal,
            'sourceMissing': source_missing,
            'safeToExpand': len(repair_numbers),
            'insufficientSource': insufficient,
        },
        'readings': records,
    }


def question_payload_hash(
    question_passages: dict[int, dict[str, Any]],
    curated_readings: dict[int, dict[str, Any]],
) -> str:
    """Hash the stable question source without coupling it to prose overlays."""
    records = []
    for source_number in sorted(question_passages):
        passage = question_passages[source_number]
        curated = curated_readings.get(source_number)
        questions = (
            curated_questions(curated)
            if curated is not None
            else vocabulary_practice_questions(passage['id'], passage['sentences'])
        )
        records.append({'sourceNumber': source_number, 'questions': questions})
    encoded = json.dumps(
        records, ensure_ascii=False, sort_keys=True, separators=(',', ':')
    ).encode('utf-8')
    return hashlib.sha256(encoded).hexdigest()


def generated_question_payload_hash(passages: dict[int, dict[str, Any]]) -> str:
    records = [
        {
            'sourceNumber': source_number,
            'questions': passage['enrichment']['questions'],
        }
        for source_number, passage in sorted(passages.items())
    ]
    encoded = json.dumps(
        records, ensure_ascii=False, sort_keys=True, separators=(',', ':')
    ).encode('utf-8')
    return hashlib.sha256(encoded).hexdigest()


def final_reading_quality_report(
    passages: dict[int, dict[str, Any]],
    canonical_quality_bands: dict[int, str],
    content_repairs: list[dict[str, Any]],
    production_quality: dict[str, Any],
) -> dict[str, Any]:
    """Summarise final editorial status without treating short sources as defects."""
    repair_numbers = {repair['sourceNumber'] for repair in content_repairs}
    records: list[dict[str, Any]] = []
    for source_number, passage in sorted(passages.items()):
        sentences = passage['sentences']
        word_count = sum(len(english_tokens(item['englishText'])) for item in sentences)
        source_missing = not sentences
        quality_band = (
            'source_missing' if source_missing
            else reading_quality_band(passage['level'], len(sentences), word_count)
        )
        records.append({
            'sourceNumber': source_number,
            'title': passage['title'],
            'level': passage['level'],
            'category': passage['category'],
            'sentenceCount': len(sentences),
            'wordCount': word_count,
            'qualityBand': quality_band,
            'contentRepairApplied': source_number in repair_numbers,
        })

    def range_summary(start: int, end: int) -> dict[str, int]:
        subset = [record for record in records if start <= record['sourceNumber'] <= end]
        source_missing = sum(record['qualityBand'] == 'source_missing' for record in subset)
        critical = sum(record['qualityBand'] == 'critical_short' for record in subset)
        safe_repairs = sum(record['contentRepairApplied'] for record in subset)
        insufficient = sum(
            canonical_quality_bands[record['sourceNumber']] == 'critical_short'
            and not record['contentRepairApplied']
            and record['qualityBand'] != 'source_missing'
            for record in subset
        )
        return {
            'criticalShort': critical,
            'qualitySafeRepaired': safe_repairs,
            'sourceMissing': source_missing,
            'insufficientSource': insufficient,
        }

    production_records = [record for record in records if record['sourceNumber'] >= 101]
    source_missing_numbers = [
        record['sourceNumber'] for record in production_records
        if record['qualityBand'] == 'source_missing'
    ]
    manual_candidates = [
        record for record in production_records
        if record['qualityBand'] == 'critical_short'
        and not record['contentRepairApplied']
        and record['sentenceCount'] > 0
    ]
    manual_candidates.sort(
        key=lambda record: (-record['sentenceCount'], -record['wordCount'], record['sourceNumber'])
    )
    manual_priority = [
        {
            'sourceNumber': record['sourceNumber'],
            'title': record['title'],
            'level': record['level'],
            'category': record['category'],
            'reason': 'Source context merits a human editorial review; automatic expansion was not safe enough.',
        }
        for record in manual_candidates[:20]
    ]
    total_sentences = sum(record['sentenceCount'] for record in records)
    translated = sum(
        bool(sentence.get('turkishText'))
        for passage in passages.values()
        for sentence in passage['sentences']
    )
    return {
        'schemaVersion': 1,
        'summary': {
            'totalReadings': len(records),
            'totalSentences': total_sentences,
            'sentencesWithTr': translated,
            'fullTrCoverage': translated == total_sentences,
            'curatedReadings': 100,
            'normal': sum(record['qualityBand'] not in ('critical_short', 'source_missing') for record in records),
            'criticalShort': sum(record['qualityBand'] == 'critical_short' for record in records),
            'sourceMissing': len(source_missing_numbers),
            'safeRepairs': len(repair_numbers),
            'insufficientSource': sum(
                canonical_quality_bands[record['sourceNumber']] == 'critical_short'
                and not record['contentRepairApplied']
                and record['qualityBand'] != 'source_missing'
                for record in production_records
            ),
        },
        'ranges': {
            '101To300': range_summary(101, 300),
            '301To500': range_summary(301, 500),
            '501To678': range_summary(501, 678),
        },
        'productionQuality': production_quality['summary'],
        'sourceMissingReadingNumbers': source_missing_numbers,
        'manualEditorialPriority': manual_priority,
    }


def reading_301_500_editorial_audit(
    passages: dict[int, dict[str, Any]],
    repairs: list[dict[str, Any]],
) -> dict[str, Any]:
    """Audit every 301–500 source before allowing a narrow safe overlay."""
    repair_numbers = {repair['sourceNumber'] for repair in repairs}
    records: list[dict[str, Any]] = []
    critical = source_missing = insufficient = normal = 0
    for source_number in range(301, 501):
        passage = passages[source_number]
        sentence_count = len(passage['sentences'])
        word_count = sum(
            len(english_tokens(sentence['englishText']))
            for sentence in passage['sentences']
        )
        if sentence_count == 0:
            quality_status = 'source_missing'
            safe = False
            reason = 'Canonical CSV has no English sentence; authored replacement is out of scope.'
            source_missing += 1
        elif reading_quality_band(passage['level'], sentence_count, word_count) == 'critical_short':
            critical += 1
            safe = source_number in repair_numbers
            if safe:
                reason = ('Canonical source has sufficient distinct detail for a small, '
                          'non-repetitive bilingual expansion without new facts.')
            else:
                reason = ('insufficient_source_for_safe_expansion; preserving a short '
                          'reading is safer than paraphrase-based filler.')
                insufficient += 1
            quality_status = 'critical_short'
        else:
            quality_status = 'normal'
            safe = False
            reason = 'No editorial expansion is required in this phase.'
            normal += 1
        records.append({
            'sourceNumber': source_number,
            'level': passage['level'],
            'title': passage['title'],
            'category': passage['category'],
            'sentenceCount': sentence_count,
            'wordCount': word_count,
            'sourceSentenceCount': sentence_count,
            'qualityStatus': quality_status,
            'safeToExpand': safe,
            'reason': reason,
        })
    if not repair_numbers.issubset({record['sourceNumber'] for record in records}):
        raise ValueError('301–500 repair is outside its audited range.')
    projected_passages = copy.deepcopy(passages)
    apply_content_repairs(projected_passages, repairs)
    critical_remaining = sum(
        len(projected_passages[source_number]['sentences']) > 0
        and reading_quality_band(
            projected_passages[source_number]['level'],
            len(projected_passages[source_number]['sentences']),
            sum(
                len(english_tokens(sentence['englishText']))
                for sentence in projected_passages[source_number]['sentences']
            ),
        ) == 'critical_short'
        for source_number in range(301, 501)
    )
    return {
        'schemaVersion': 1,
        'summary': {
            'audited': len(records),
            'criticalShortBefore': critical,
            'safeToExpand': len(repair_numbers),
            'qualitySafeExpanded': len(repair_numbers),
            'insufficientSourceForSafeExpansion': insufficient,
            'sourceMissing': source_missing,
            'criticalShortRemaining': critical_remaining,
            'normal': normal,
        },
        'readings': records,
    }


def passages_by_source_number(
    passages: dict[str, dict[str, Any]],
) -> dict[int, dict[str, Any]]:
    result = {source_number_for(passage): passage for passage in passages.values()}
    if set(result) != set(range(1, 679)):
        raise ValueError('Passage source-number coverage is invalid.')
    return result


def apply_translation_repairs(
    passages: dict[int, dict[str, Any]], repairs: list[dict[str, Any]]
) -> None:
    for repair in repairs:
        passage = passages[repair['sourceNumber']]
        if passage['id'] != repair['readingId']:
            raise ValueError('Translation repair reading ID does not match canonical source.')
        sentence = next(
            (item for item in passage['sentences'] if item['index'] == repair['sentenceIndex']),
            None,
        )
        if sentence is None or sentence['englishText'] != repair['englishText']:
            raise ValueError('Translation repair English source does not match canonical sentence.')
        if sentence['turkishText'] is not None:
            raise ValueError('Translation repair may only fill a missing canonical Turkish sentence.')
        sentence['turkishText'] = repair['turkishText']


def apply_content_repairs(
    passages: dict[int, dict[str, Any]], repairs: list[dict[str, Any]]
) -> dict[int, str]:
    applied: dict[int, str] = {}
    for repair in repairs:
        source_number = repair['sourceNumber']
        passage = passages[source_number]
        if passage['id'] != repair['readingId']:
            raise ValueError('Content repair reading ID does not match canonical source.')
        word_count = sum(
            len(english_tokens(sentence['englishText']))
            for sentence in passage['sentences']
        )
        if reading_quality_band(passage['level'], len(passage['sentences']), word_count) != 'critical_short':
            raise ValueError('Content repair target is not a critical-short canonical reading.')
        next_index = max((item['index'] for item in passage['sentences']), default=0) + 1
        passage['sentences'].extend({
            'index': next_index + offset,
            'englishText': sentence['englishText'],
            'turkishText': sentence['turkishText'],
        } for offset, sentence in enumerate(repair['appendSentences']))
        applied[source_number] = repair['reason']
    return applied


def write_quality_reports(
    source_dir: Path,
    passages: dict[int, dict[str, Any]],
    translation_repairs: list[dict[str, Any]],
    content_repair_reasons: dict[int, str],
    canonical_quality_bands: dict[int, str],
) -> dict[str, Any]:
    """Write deterministic, reviewable quality audits beside source overlays."""
    translation_missing: list[dict[str, Any]] = []
    length_records: list[dict[str, Any]] = []
    translated = total_sentences = complete = partial = zero = 0
    before_critical = after_critical = repaired_critical = 0
    bands: Counter[str] = Counter()
    for source_number, passage in sorted(passages.items()):
        sentences = passage['sentences']
        sentence_count = len(sentences)
        translated_count = sum(
            1 for sentence in sentences if clean(sentence.get('turkishText'))
        )
        missing_count = sentence_count - translated_count
        translated += translated_count
        total_sentences += sentence_count
        if missing_count == 0:
            complete += 1
        elif translated_count == 0:
            zero += 1
        else:
            partial += 1
        for sentence in sentences:
            if clean(sentence.get('turkishText')):
                continue
            translation_missing.append({
                'sourceNumber': source_number,
                'readingId': passage['id'],
                'sentenceIndex': sentence['index'],
                'englishText': sentence['englishText'],
            })
        word_count = sum(len(english_tokens(sentence['englishText'])) for sentence in sentences)
        quality_band = reading_quality_band(passage['level'], sentence_count, word_count)
        bands[quality_band] += 1
        canonical_band = canonical_quality_bands.get(source_number, quality_band)
        was_critical = canonical_band == 'critical_short'
        before_critical += int(was_critical)
        after_critical += int(quality_band == 'critical_short')
        repaired_critical += int(
            was_critical
            and source_number in content_repair_reasons
            and quality_band != 'critical_short'
        )
        length_records.append({
            'sourceNumber': source_number,
            'level': passage['level'],
            'sentenceCount': sentence_count,
            'wordCount': word_count,
            'estimatedMinutes': (
                max(1, (word_count + READING_WORDS_PER_MINUTE - 1) // READING_WORDS_PER_MINUTE)
                if word_count else 0
            ),
            'translationCoverage': (
                round(translated_count / sentence_count, 6) if sentence_count else 1.0
            ),
            'qualityBand': quality_band,
            'wasCriticalShort': was_critical,
            'contentRepairApplied': source_number in content_repair_reasons,
            'repairStatus': (
                'unrecoverable_source_missing' if not sentences
                else ('repaired' if source_number in content_repair_reasons else None)
            ),
        })
    reports_dir = source_dir / REPORTS_DIRECTORY
    translation_report = {
        'schemaVersion': 1,
        'summary': {
            'totalReadings': len(passages),
            'totalSentences': total_sentences,
            'sentencesWithTr': translated,
            'sentencesWithoutTr': total_sentences - translated,
            'readingsWithCompleteTr': complete,
            'readingsWithPartialTr': partial,
            'readingsWithZeroTr': zero,
            'translationRepairs': len(translation_repairs),
        },
        'missingSentences': translation_missing,
    }
    length_report = {
        'schemaVersion': 1,
        'thresholds': {
            'A1_A2': {'minSentences': 8, 'minWords': 80},
            'B1_B2': {'minSentences': 10, 'minWords': 120},
            'C1_C2': {'minSentences': 12, 'minWords': 150},
        },
        'summary': {
            'totalReadings': len(passages),
            'criticalShortBefore': before_critical,
            'criticalShort': after_critical,
            'criticalShortRepaired': repaired_critical,
            'short': bands['short'],
            'normal': bands['normal'],
            'long': bands['long'],
        },
        'readings': length_records,
    }
    write_json(reports_dir / 'reading_translation_audit_v1.json', translation_report)
    write_json(reports_dir / 'reading_length_audit_v1.json', length_report)
    return {
        'translation': translation_report['summary'],
        'length': length_report['summary'],
    }


def build(
    source_dir: Path,
    output_dir: Path,
    curated_package: Path | None = None,
) -> dict[str, Any]:
    words_source = source_dir / 'canonical' / 'words' / 'yds_words_set_001.csv'
    passages_source = source_dir / 'canonical' / 'readings' / 'reading_passages.csv'
    sentences_source = source_dir / 'canonical' / 'readings' / 'reading_sentences.csv'
    dictionary_source = source_dir / 'canonical' / 'dictionary' / 'dictionary_tr_en.xlsx'
    pack_map_source = source_dir / 'mappings' / 'word_pack_reclassification_v1.json'
    word_tr_meaning_corrections_source = (
        source_dir / QUALITY_DIRECTORY / WORD_TR_MEANING_CORRECTIONS_FILENAME
    )
    pre_curated_generated_questions_backup_source = (
        source_dir / 'legacy' / 'pre_curated_generated_questions_backup_v1.json'
    )
    translation_repairs_source = (
        source_dir / QUALITY_DIRECTORY / 'reading_translation_repairs_v1.json'
    )
    canonical_language_correction_sources = [
        source_dir / QUALITY_DIRECTORY / filename
        for filename in CANONICAL_LANGUAGE_CORRECTION_FILENAMES
    ]
    canonical_editorial_review_101_300_source = (
        source_dir / QUALITY_DIRECTORY / CANONICAL_EDITORIAL_REVIEW_101_300_FILENAME
    )
    content_repair_sources = [
        source_dir / QUALITY_DIRECTORY / filename
        for filename in CONTENT_REPAIR_FILENAMES
    ]
    legacy_base_pre_final_polish_repairs_source = (
        source_dir / LEGACY_BASE_PRE_FINAL_POLISH_REPAIRS_RELATIVE_PATH
    )
    legacy_pre_polish_repairs_source = (
        source_dir / LEGACY_101_300_PRE_POLISH_REPAIRS_RELATIVE_PATH
    )
    legacy_101_300_pre_final_polish_repairs_source = (
        source_dir / LEGACY_101_300_PRE_FINAL_POLISH_REPAIRS_RELATIVE_PATH
    )
    legacy_301_500_pre_final_polish_repairs_source = (
        source_dir / LEGACY_301_500_PRE_FINAL_POLISH_REPAIRS_RELATIVE_PATH
    )
    source_baseline = source_dir / SOURCE_BASELINE_RELATIVE_PATH
    curated_package = curated_package or (
        source_dir / DEFAULT_CURATED_READINGS_RELATIVE_PATH
    )
    for source in (
        words_source,
        passages_source,
        sentences_source,
        dictionary_source,
        word_tr_meaning_corrections_source,
        pre_curated_generated_questions_backup_source,
        translation_repairs_source,
        *canonical_language_correction_sources,
        canonical_editorial_review_101_300_source,
        *content_repair_sources,
        legacy_base_pre_final_polish_repairs_source,
        legacy_pre_polish_repairs_source,
        legacy_101_300_pre_final_polish_repairs_source,
        legacy_301_500_pre_final_polish_repairs_source,
        source_baseline,
        curated_package,
    ):
        if not source.is_file():
            raise FileNotFoundError(source)
    curated_readings = load_curated_readings(curated_package)

    word_pack_names: dict[str, str] = {}
    if pack_map_source.is_file():
        pack_map = json.loads(pack_map_source.read_text(encoding='utf-8'))
        word_pack_names = {
            clean(item.get('word_id')): clean(item.get('target_pack_name'))
            for item in pack_map.get('items', [])
            if clean(item.get('word_id')) and clean(item.get('target_pack_name'))
        }

    word_rows = read_csv(words_source)
    word_content_quality_audit = word_content_quality_audit_report(
        word_rows,
        load_word_tr_meaning_corrections(word_tr_meaning_corrections_source),
    )
    seen_words: set[tuple[str, str]] = set()
    words_by_pack: dict[str, list[dict[str, Any]]] = defaultdict(list)
    primary_word_ids: dict[str, list[str]] = defaultdict(list)
    all_pack_names: set[str] = {'YDS Set 001'}
    for row in word_rows:
        english = clean(row.get('en_word'))
        meaning = clean(row.get('tr_meaning'))
        examples = (clean(row.get('example_en')), clean(row.get('example_tr')))
        if any(has_invalid_spreadsheet_token(value) for value in (english, meaning, *examples)):
            raise ValueError('Word source contains an invalid spreadsheet-error token.')
        pos = canonical_pos(row.get('pos'))
        if not english or not meaning:
            continue
        dedupe_key = (normalized(english), pos)
        if dedupe_key in seen_words:
            continue
        seen_words.add(dedupe_key)
        identifier = word_id(english, pos)
        target_pack_name = word_pack_names.get(identifier, 'YDS Set 001')
        all_pack_names.add(target_pack_name)
        primary_word_ids[normalize_dictionary_key(english)].append(identifier)
        words_by_pack[target_pack_name].append({
            'id': identifier,
            'packId': pack_id(target_pack_name),
            'enWord': english,
            'trMeaning': meaning,
            'pos': pos,
            'exampleEn': clean(row.get('example_en')) or english,
            'exampleTr': nullable(row.get('example_tr')),
            'synonymsRaw': nullable(row.get('synonyms_raw')),
            'antonymsRaw': nullable(row.get('antonyms_raw')),
            'notes': nullable(row.get('notes')),
            'level': nullable(row.get('level')),
            'tags': parse_tag_list(row.get('tags_raw')),
        })

    passage_rows = read_csv(passages_source)
    passages: dict[str, dict[str, Any]] = {}
    for row in passage_rows:
        title = clean(row.get('title'))
        source_pack = clean(row.get('pack_name'))
        if not title or not source_pack:
            continue
        all_pack_names.add(source_pack)
        key = normalized(title)
        if key in passages:
            raise ValueError(f'Duplicate normalized passage title: {title!r}')
        passages[key] = {
            'id': passage_id(title), 'packId': pack_id(source_pack), 'title': title,
            'level': nullable(row.get('level')), 'category': nullable(row.get('Category')),
            'tags': parse_tag_list(row.get('tags_raw')), 'author': None,
            'durationMinutes': None, 'coverAsset': None, 'coverAltText': None,
            'sentences': [], 'enrichment': {},
        }

    sentence_rows = read_csv(sentences_source)
    grouped_sentences: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in sentence_rows:
        title = clean(row.get('passage_title'))
        english = clean(row.get('sentence_en'))
        raw_index = clean(row.get('idx'))
        if not any((title, english, raw_index, clean(row.get('sentence_tr')))):
            continue
        if not title or not english or not raw_index:
            continue
        try:
            index = int(raw_index)
        except ValueError as error:
            raise ValueError(f'Invalid sentence index for {title!r}: {raw_index!r}') from error
        grouped_sentences[normalized(title)].append({
            'index': index, 'englishText': english, 'turkishText': nullable(row.get('sentence_tr')),
        })

    sentence_count = 0
    for title_key, sentences in grouped_sentences.items():
        passage = passages.get(title_key)
        if passage is None:
            raise ValueError(f'Sentence has no passage: {title_key!r}')
        indexes = [item['index'] for item in sentences]
        if any(index <= 0 for index in indexes) or len(indexes) != len(set(indexes)):
            for index, sentence in enumerate(sentences, start=1):
                sentence['index'] = index
        else:
            sentences.sort(key=lambda item: item['index'])
        passage['sentences'] = sentences
        sentence_count += len(sentences)

    numbered_passages = passages_by_source_number(passages)
    validate_canonical_source_baseline(source_baseline, passages)
    translation_repairs = load_translation_repairs(translation_repairs_source)
    apply_translation_repairs(numbered_passages, translation_repairs)
    # Derived questions deliberately retain their existing canonical source.
    # Language corrections affect the displayed passage only, never questions.
    question_passages = copy.deepcopy(numbered_passages)
    canonical_language_overlay = load_canonical_language_correction_overlays(
        canonical_language_correction_sources
    )
    canonical_language_audit = canonical_language_audit_report(
        numbered_passages, canonical_language_overlay['corrections']
    )
    canonical_editorial_review_101_300 = canonical_editorial_review_101_300_report(
        numbered_passages,
        canonical_language_overlay['corrections'],
        load_manual_editorial_review_101_300(canonical_editorial_review_101_300_source),
    )
    canonical_quality_bands = {
        source_number: reading_quality_band(
            passage['level'],
            len(passage['sentences']),
            sum(len(english_tokens(sentence['englishText'])) for sentence in passage['sentences']),
        )
        for source_number, passage in numbered_passages.items()
    }
    base_content_repairs = load_content_repairs(content_repair_sources[0])
    range_101_300_content_repairs = load_content_repairs(content_repair_sources[1])
    range_301_500_content_repairs = load_content_repairs(content_repair_sources[2])
    range_501_678_content_repairs = load_content_repairs(content_repair_sources[3])
    legacy_base_pre_final_polish_repairs = load_content_repairs(
        legacy_base_pre_final_polish_repairs_source
    )
    legacy_pre_polish_repairs = load_content_repairs(legacy_pre_polish_repairs_source)
    legacy_101_300_pre_final_polish_repairs = load_content_repairs(
        legacy_101_300_pre_final_polish_repairs_source
    )
    legacy_301_500_pre_final_polish_repairs = load_content_repairs(
        legacy_301_500_pre_final_polish_repairs_source
    )
    base_language_audit = language_polish_audit(
        legacy_base_pre_final_polish_repairs,
        base_content_repairs,
        numbered_passages,
    )
    final_language_audit_101_300 = language_polish_audit(
        legacy_101_300_pre_final_polish_repairs,
        range_101_300_content_repairs,
        numbered_passages,
    )
    final_language_audit_301_500 = language_polish_audit(
        legacy_301_500_pre_final_polish_repairs,
        range_301_500_content_repairs,
        numbered_passages,
    )
    language_audit = {
        'schemaVersion': 1,
        'summary': merge_language_polish_summaries([
            base_language_audit,
            final_language_audit_101_300,
            final_language_audit_301_500,
        ]),
        'ranges': {
            '101To300': merge_language_polish_summaries([
                base_language_audit,
                final_language_audit_101_300,
            ]),
            '301To500': final_language_audit_301_500['summary'],
        },
        'components': {
            'base102And122': base_language_audit,
            '101To300V4': final_language_audit_101_300,
            '301To500V2': final_language_audit_301_500,
        },
    }
    repair_quality_101_300 = production_repair_quality_audit(
        base_content_repairs + range_101_300_content_repairs, numbered_passages
    )
    repair_quality_301_500 = production_repair_quality_audit(
        range_301_500_content_repairs, numbered_passages
    )
    repair_quality_501_678 = production_repair_quality_audit(
        range_501_678_content_repairs, numbered_passages
    )
    content_repairs = load_content_repair_overlays(content_repair_sources)
    production_repair_quality = production_repair_quality_audit(
        content_repairs, numbered_passages
    )
    editorial_301_500_audit = reading_301_500_editorial_audit(
        numbered_passages, range_301_500_content_repairs
    )
    editorial_501_678_audit = reading_501_678_editorial_audit(
        numbered_passages, range_501_678_content_repairs
    )
    write_json(
        source_dir / REPORTS_DIRECTORY / 'reading_101_300_language_polish_audit_v4.json',
        final_language_audit_101_300,
    )
    write_json(
        source_dir / REPORTS_DIRECTORY / 'reading_301_500_language_polish_audit_v2.json',
        final_language_audit_301_500,
    )
    write_json(
        source_dir / REPORTS_DIRECTORY / 'reading_101_500_final_language_polish_audit_v1.json',
        language_audit,
    )
    write_json(
        source_dir / REPORTS_DIRECTORY / 'reading_301_500_editorial_audit_v1.json',
        editorial_301_500_audit,
    )
    write_json(
        source_dir / REPORTS_DIRECTORY / 'reading_501_678_editorial_audit_v1.json',
        editorial_501_678_audit,
    )
    write_json(
        source_dir / REPORTS_DIRECTORY / CANONICAL_LANGUAGE_AUDIT_FILENAME,
        canonical_language_audit,
    )
    write_json(
        source_dir / REPORTS_DIRECTORY / CANONICAL_EDITORIAL_REVIEW_101_300_FILENAME,
        canonical_editorial_review_101_300,
    )
    apply_canonical_language_corrections(
        numbered_passages, canonical_language_overlay['corrections']
    )
    content_repair_reasons = apply_content_repairs(
        numbered_passages, base_content_repairs
    )

    for source_number, curated in curated_readings.items():
        passage = numbered_passages[source_number]
        passage['sentences'] = [
            {
                'index': sentence['index'],
                'englishText': curated_text(sentence, 'en'),
                'turkishText': curated_text(sentence, 'tr'),
            }
            for sentence in curated['sentences']
        ]
        canonical_quality_bands[source_number] = reading_quality_band(
            passage['level'],
            len(passage['sentences']),
            sum(len(english_tokens(sentence['englishText'])) for sentence in passage['sentences']),
        )

    # Keep derived vocabulary practice stable while editorial overlays improve
    # reading prose.  101–300 deliberately uses the pre-polish v2 question
    # source; 301–500 keeps its canonical question source.  This prevents a
    # language-only repair or a new reading append from silently changing a
    # learner's existing questions, options, or answers.
    apply_content_repairs(question_passages, legacy_base_pre_final_polish_repairs)
    apply_content_repairs(question_passages, legacy_pre_polish_repairs)
    expected_question_hash = question_payload_hash(question_passages, curated_readings)

    document_frequency: Counter[str] = Counter()
    for passage in passages.values():
        document_frequency.update({
            token
            for sentence in passage['sentences']
            for token in english_tokens(sentence['englishText'])
        })

    # Keep the document-frequency corpus stable for untouched readings.  The
    # range overlay is editorial content for 101–300, not a reason to change
    # focus-word ranking in 301–678.
    content_repair_reasons.update(
        apply_content_repairs(numbered_passages, range_101_300_content_repairs)
    )
    content_repair_reasons.update(
        apply_content_repairs(numbered_passages, range_301_500_content_repairs)
    )
    content_repair_reasons.update(
        apply_content_repairs(numbered_passages, range_501_678_content_repairs)
    )

    enrichment_audit = {
        'wordCountReadings': 0,
        'durationReadings': 0,
        'focusWordReadings': 0,
        'summaryReadings': 0,
        'questionReadings': 0,
        'totalQuestions': 0,
        'comprehensionQuestions': 0,
        'vocabularyPracticeQuestions': 0,
        'curatedReadings': 0,
        'curatedSentences': 0,
        'curatedQuestions': 0,
        'translationRepairs': len(translation_repairs),
        'contentRepairs': len(content_repairs),
    }
    for passage in passages.values():
        source_number, display_title, turkish_title = display_titles(passage['title'])
        source_number_int = source_number_for(passage)
        curated = curated_readings.get(source_number_int)
        sentences = passage['sentences']
        if curated is not None:
            display_title = curated_text(curated, 'replacement_title_en')
            turkish_title = curated_text(curated, 'replacement_title_tr')
            summary = curated_text(curated, 'summary_en')
            summary_tr: str | None = curated_text(curated, 'summary_tr')
            summary_type = 'curated'
            questions = curated_questions(curated)
            content_source = 'curated_v2'
            enrichment_audit['curatedReadings'] += 1
            enrichment_audit['curatedSentences'] += len(sentences)
            enrichment_audit['curatedQuestions'] += len(questions)
        else:
            summary = extractive_summary(sentences)
            summary_tr = None
            summary_type = 'extractive'
            questions = vocabulary_practice_questions(
                passage['id'],
                question_passages[source_number_int]['sentences'],
            )
            content_source = 'derived_v1'
        word_count = sum(
            len(english_tokens(sentence['englishText'])) for sentence in sentences
        )
        focus_ids = focus_word_ids(
            sentences,
            primary_word_ids,
            document_frequency,
            len(passages),
        )
        enrichment = {
            'schemaVersion': 1,
            'sourceNumber': source_number,
            'displayTitle': display_title,
            'turkishTitle': turkish_title,
            'wordCount': word_count,
            'estimatedReadingMinutes': (
                max(1, (word_count + READING_WORDS_PER_MINUTE - 1) // READING_WORDS_PER_MINUTE)
                if word_count else 0
            ),
            'focusWordIds': focus_ids,
            'summary': summary,
            'summaryType': summary_type,
            'questions': questions,
            'contentSource': content_source,
        }
        if curated is not None:
            enrichment['summaryTr'] = summary_tr
        passage['enrichment'] = enrichment
        enrichment_audit['wordCountReadings'] += int(word_count > 0)
        enrichment_audit['durationReadings'] += int(word_count > 0)
        enrichment_audit['focusWordReadings'] += int(bool(focus_ids))
        enrichment_audit['summaryReadings'] += int(summary is not None)
        enrichment_audit['questionReadings'] += int(bool(questions))
        enrichment_audit['totalQuestions'] += len(questions)
        enrichment_audit['comprehensionQuestions'] += sum(
            question.get('questionCategory') == 'comprehension'
            for question in questions
        )
        enrichment_audit['vocabularyPracticeQuestions'] += sum(
            question.get('questionCategory') == 'vocabulary_practice'
            for question in questions
        )

    if enrichment_audit['curatedReadings'] != len(curated_readings):
        raise ValueError('Every curated reading must map to exactly one source_number.')
    actual_question_hash = generated_question_payload_hash(numbered_passages)
    if actual_question_hash != expected_question_hash:
        raise ValueError('Editorial prose overlays changed the preserved question payload.')
    sentence_count = sum(len(passage['sentences']) for passage in passages.values())
    quality_audit = write_quality_reports(
        source_dir,
        numbered_passages,
        translation_repairs,
        content_repair_reasons,
        canonical_quality_bands,
    )
    final_quality_report = final_reading_quality_report(
        numbered_passages,
        canonical_quality_bands,
        content_repairs,
        production_repair_quality,
    )
    write_json(
        source_dir / REPORTS_DIRECTORY / 'reading_quality_final_v1.json',
        final_quality_report,
    )
    language_quality_final = reading_language_quality_final_report(
        numbered_passages, canonical_language_audit
    )
    write_json(
        source_dir / REPORTS_DIRECTORY / LANGUAGE_QUALITY_FINAL_FILENAME,
        language_quality_final,
    )

    if output_dir.exists():
        shutil.rmtree(output_dir)
    (output_dir / 'words').mkdir(parents=True)
    (output_dir / 'readings' / 'items').mkdir(parents=True)

    pack_records = []
    word_index = []
    for name in sorted(all_pack_names, key=str.casefold):
        identifier = pack_id(name)
        entries = sorted(words_by_pack[name], key=lambda item: item['enWord'].casefold())
        file_name = f'{identifier}.json'
        write_json(output_dir / 'words' / file_name, {'packId': identifier, 'words': entries})
        record = {'id': identifier, 'name': name, 'wordCount': len(entries)}
        pack_records.append(record)
        word_index.append({**record, 'file': f'words/{file_name}'})

    reading_index = []
    for passage in sorted(passages.values(), key=lambda item: item['title'].casefold()):
        identifier = passage['id']
        file_name = f'{identifier}.json'
        write_json(output_dir / 'readings' / 'items' / file_name, passage)
        enrichment = passage['enrichment']
        reading_index.append({
            key: passage[key] for key in (
                'id', 'packId', 'title', 'level', 'category', 'tags',
                'author', 'durationMinutes', 'coverAsset', 'coverAltText',
            )
        } | {
            'sentenceCount': len(passage['sentences']),
            'sourceNumber': enrichment['sourceNumber'],
            'displayTitle': enrichment['displayTitle'],
            'turkishTitle': enrichment['turkishTitle'],
            'wordCount': enrichment['wordCount'],
            'estimatedReadingMinutes': enrichment['estimatedReadingMinutes'],
            'file': f'readings/items/{file_name}',
        })

    write_json(output_dir / 'words' / 'index.json', {'packs': word_index})
    write_json(output_dir / 'readings' / 'index.json', {'readings': reading_index})
    dictionary = build_dictionary(dictionary_source, output_dir)
    write_json(
        source_dir / REPORTS_DIRECTORY / WORD_CONTENT_QUALITY_AUDIT_FILENAME,
        word_content_quality_audit,
    )
    manifest = {
        'schemaVersion': 1, 'generatedAt': datetime.now(UTC).isoformat(), 'contentVersion': 'v1',
        'counts': {
            'words': sum(len(items) for items in words_by_pack.values()),
            'readings': len(passages), 'sentences': sentence_count,
            'dictionaryEntries': dictionary['recordCount'],
            'dictionaryHeadwords': dictionary['uniqueNormalizedHeadwords'],
        },
        'packs': pack_records, 'wordsIndex': 'words/index.json',
        'readingsIndex': 'readings/index.json', 'dictionaryIndex': 'dictionary/index.json',
        'readingEnrichment': {
            'schemaVersion': 1,
            'wordsPerMinute': READING_WORDS_PER_MINUTE,
            **enrichment_audit,
        },
        'readingQualityAudit': quality_audit,
        'finalReadingQualityAudit': final_quality_report['summary'],
        'canonicalLanguageQualityAudit': canonical_language_audit['summary'],
        'canonicalEditorialReview101To300': canonical_editorial_review_101_300['summary'],
        'wordContentQualityAudit': word_content_quality_audit['summary'],
        'readingLanguageQualityFinal': language_quality_final['summary'],
        'editorialRepairAudit': language_audit['summary'],
        'readingQuestionIntegrity': {
            'schemaVersion': 1,
            'payloadSha256': actual_question_hash,
            'curatedReadings': len(curated_readings),
            'derivedReadings': len(passages) - len(curated_readings),
        },
        'productionEditorialQuality': {
            'repairs101To300V4': repair_quality_101_300['summary'],
            'repairs301To500V2': repair_quality_301_500['summary'],
            'repairs501To678V1': repair_quality_501_678['summary'],
            'allProductionOverlays': production_repair_quality['summary'],
        },
        'sourceChecksums': {
            'words': source_hash(words_source), 'passages': source_hash(passages_source),
            'sentences': source_hash(sentences_source), 'dictionary': source_hash(dictionary_source),
            'curatedReadings': source_hash(curated_package),
            'preCuratedGeneratedQuestionsBackup': source_hash(
                pre_curated_generated_questions_backup_source
            ),
            'translationRepairs': source_hash(translation_repairs_source),
            'canonicalLanguageCorrections': source_hash(
                canonical_language_correction_sources[0]
            ),
            'canonicalLanguageCorrections101To300V3': source_hash(
                canonical_language_correction_sources[1]
            ),
            'wordTrMeaningCorrections': source_hash(word_tr_meaning_corrections_source),
            'canonicalEditorialReview101To300': source_hash(
                canonical_editorial_review_101_300_source
            ),
            'contentRepairs': source_hash(content_repair_sources[0]),
            'contentRepairs101To300': source_hash(content_repair_sources[1]),
            'contentRepairs301To500': source_hash(content_repair_sources[2]),
            'contentRepairs501To678': source_hash(content_repair_sources[3]),
            'legacyQuestionBaseSource': source_hash(
                legacy_base_pre_final_polish_repairs_source
            ),
            'legacyEditorialRepairHistory': source_hash(legacy_pre_polish_repairs_source),
            'legacy101To300FinalPolishHistory': source_hash(
                legacy_101_300_pre_final_polish_repairs_source
            ),
            'legacy301To500FinalPolishHistory': source_hash(
                legacy_301_500_pre_final_polish_repairs_source
            ),
            'canonicalSourceBaselineV2': source_hash(source_baseline),
            **({'wordPackMap': source_hash(pack_map_source)} if pack_map_source.is_file() else {}),
        },
    }
    write_json(output_dir / 'manifest.json', manifest)
    return {**manifest, 'dictionaryAudit': dictionary['audit']}


def main() -> int:
    parser = argparse.ArgumentParser(description='Build public PASSAGETR static content.')
    parser.add_argument('--source-dir', type=Path, default=ROOT / 'source_data')
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'assets' / 'content' / 'v1')
    parser.add_argument(
        '--curated-package',
        type=Path,
        help='Optional curated reading package override. Defaults to source_data/curated.',
    )
    args = parser.parse_args()
    manifest = build(
        args.source_dir.resolve(),
        args.output_dir.resolve(),
        args.curated_package.resolve() if args.curated_package else None,
    )
    print(json.dumps({**manifest['counts'], 'dictionaryAudit': manifest['dictionaryAudit']}, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
