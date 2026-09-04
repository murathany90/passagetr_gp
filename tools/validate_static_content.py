#!/usr/bin/env python3
"""Validate the public PASSAGETR static-content contract.

The production prose contract is intentionally small: word records come from
one canonical CSV, and every generated reading sentence comes from one
canonical CSV.  Question sources are checked separately because they are not
part of the reading body.
"""

from __future__ import annotations

import csv
import hashlib
import json
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import build_static_content as builder  # noqa: E402


SOURCE = ROOT / 'source_data'
CONTENT = ROOT / 'assets' / 'content' / 'v1'
WORDS_SOURCE = SOURCE / 'canonical' / 'words' / builder.WORDS_CANONICAL_FILENAME
OLD_WORDS_SOURCE = SOURCE / 'canonical' / 'words' / ('yds_words' + '_set_001.csv')
PASSAGES_SOURCE = SOURCE / 'canonical' / 'readings' / 'reading_passages.csv'
SENTENCES_SOURCE = SOURCE / 'canonical' / 'readings' / 'reading_sentences.csv'
QUESTIONS_SOURCE = SOURCE / 'canonical' / 'readings' / builder.DERIVED_QUESTIONS_FILENAME
CURATED_SOURCE = SOURCE / builder.DEFAULT_CURATED_READINGS_RELATIVE_PATH
DICTIONARY_SOURCE = SOURCE / 'canonical' / 'dictionary' / 'dictionary_tr_en.xlsx'

EXPECTED_WORDS = 7500
EXPECTED_READINGS = 678
EXPECTED_SENTENCES = 6275
EXPECTED_WORD_TAGS = 66
EXPECTED_DICTIONARY_ENTRIES = 121772
EXPECTED_DICTIONARY_HEADWORDS = 121501
WORD_FIELDS = {
    'en_word', 'tr_meaning', 'pos', 'example_en', 'example_tr',
    'synonyms_raw', 'antonyms_raw', 'level', 'tags_raw', 'notes',
}
REQUIRED_WORD_FIELDS = (
    'en_word', 'tr_meaning', 'pos', 'example_en', 'example_tr',
    'level', 'tags_raw', 'notes',
)
TEXT_FILE_SUFFIXES = {'.dart', '.json', '.md', '.py', '.yaml', '.yml'}


def fail(message: str) -> None:
    raise ValueError(message)


def load_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(payload, dict):
        fail(f'JSON object expected: {path.relative_to(ROOT)}')
    return payload


def source_number(title: str) -> int:
    match = re.match(r'^\s*(\d+)\s*[-.)]', builder.clean(title))
    if match is None:
        fail(f'Invalid canonical passage title: {title!r}')
    return int(match.group(1))


def canonical_readings() -> tuple[dict[int, dict[str, Any]], int, list[int]]:
    passage_rows = builder.read_csv(PASSAGES_SOURCE)
    if len(passage_rows) != EXPECTED_READINGS:
        fail(f'Expected {EXPECTED_READINGS} passage rows, got {len(passage_rows)}')
    passages: dict[int, dict[str, Any]] = {}
    titles: dict[str, int] = {}
    for row in passage_rows:
        title = builder.clean(row.get('title'))
        number = source_number(title)
        if number in passages or number < 1 or number > EXPECTED_READINGS:
            fail(f'Duplicate/out-of-range passage number: {number}')
        key = builder.normalized(title)
        if not title or key in titles:
            fail(f'Duplicate/blank passage title: {title!r}')
        if not builder.clean(row.get('pack_name')):
            fail(f'Blank pack name in reading {number:03d}')
        passages[number] = {
            'title': title,
            'id': builder.passage_id(title),
            'sentences': [],
        }
        titles[key] = number
    if set(passages) != set(range(1, EXPECTED_READINGS + 1)):
        fail('Passage CSV does not cover source numbers 001–678.')

    sentence_rows = builder.read_csv(SENTENCES_SOURCE)
    for row_number, row in enumerate(sentence_rows, start=2):
        title = builder.clean(row.get('passage_title'))
        english = builder.clean(row.get('sentence_en'))
        turkish = builder.clean(row.get('sentence_tr'))
        raw_index = builder.clean(row.get('idx'))
        if not all((title, english, turkish, raw_index)):
            fail(f'Blank canonical EN/TR sentence value at CSV row {row_number}.')
        number = titles.get(builder.normalized(title))
        if number is None:
            fail(f'Sentence row {row_number} has no canonical passage.')
        try:
            index = int(raw_index)
        except ValueError as error:
            raise ValueError(f'Invalid sentence index at CSV row {row_number}.') from error
        if index <= 0:
            fail(f'Non-positive sentence index at CSV row {row_number}.')
        passages[number]['sentences'].append({
            'index': index,
            'englishText': english,
            'turkishText': turkish,
        })
    for number, passage in passages.items():
        indexes = [sentence['index'] for sentence in passage['sentences']]
        if len(indexes) != len(set(indexes)):
            fail(f'Duplicate sentence index in reading {number:03d}.')
        passage['sentences'].sort(key=lambda sentence: sentence['index'])
    if len(sentence_rows) != EXPECTED_SENTENCES:
        fail(f'Expected {EXPECTED_SENTENCES} canonical sentence rows, got {len(sentence_rows)}')
    source_missing = [
        number for number, passage in passages.items() if not passage['sentences']
    ]
    return passages, len(sentence_rows), source_missing


def validate_words() -> dict[str, int]:
    if OLD_WORDS_SOURCE.exists():
        fail('Obsolete previous word source still exists.')
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
    needle = 'yds_words' + '_set_001.csv'
    matches: list[Path] = []
    excluded = {'.git', '.dart_tool', '.migration_tmp', 'build'}
    for path in ROOT.rglob('*'):
        if not path.is_file() or excluded.intersection(path.parts):
            continue
        if path.suffix.lower() not in TEXT_FILE_SUFFIXES:
            continue
        try:
            if needle in path.read_text(encoding='utf-8', errors='ignore'):
                matches.append(path)
        except OSError:
            continue
    if matches:
        relative = ', '.join(str(path.relative_to(ROOT)) for path in matches)
        fail(f'Stale old word-source references: {relative}')
    return 0


def validate_no_sentence_overlay_sources() -> int:
    # The complete tracked source-data allowlist intentionally contains no
    # repair/override layer.  Reading body is therefore unambiguously the CSV.
    allowed = {
        WORDS_SOURCE.resolve(), PASSAGES_SOURCE.resolve(), SENTENCES_SOURCE.resolve(),
        QUESTIONS_SOURCE.resolve(), CURATED_SOURCE.resolve(), DICTIONARY_SOURCE.resolve(),
    }
    files = {path.resolve() for path in SOURCE.rglob('*') if path.is_file()}
    unexpected = sorted(files - allowed)
    if unexpected:
        relative = ', '.join(str(path.relative_to(ROOT)) for path in unexpected)
        fail(f'Unexpected non-canonical source-data files remain: {relative}')
    return 0


def validate_generated_content(
    passages: dict[int, dict[str, Any]],
    sentence_rows: int,
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
        'passages': 'canonical/readings/reading_passages.csv',
        'sentences': 'canonical/readings/reading_sentences.csv',
        'productionSentenceOverlays': 0,
        'sourceMissingReadingNumbers': source_missing,
    }:
        fail(f'Unexpected reading canonical source declaration: {source!r}')
    checksums = manifest.get('sourceChecksums')
    expected_checksums = {
        'words': builder.source_hash(WORDS_SOURCE),
        'passages': builder.source_hash(PASSAGES_SOURCE),
        'sentences': builder.source_hash(SENTENCES_SOURCE),
        'derivedQuestions': builder.source_hash(QUESTIONS_SOURCE),
        'dictionary': builder.source_hash(DICTIONARY_SOURCE),
        'curatedReadings': builder.source_hash(CURATED_SOURCE),
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

    curated = builder.load_curated_readings(CURATED_SOURCE)
    derived = builder.load_derived_questions(QUESTIONS_SOURCE)
    index = load_json(CONTENT / 'readings' / 'index.json').get('readings')
    if not isinstance(index, list) or len(index) != EXPECTED_READINGS:
        fail('Generated reading index is incomplete.')
    indexed_numbers: set[int] = set()
    total_sentences = 0
    for entry in index:
        if not isinstance(entry, dict):
            fail('Generated reading index entry is invalid.')
        number = int(entry.get('sourceNumber'))
        if number in indexed_numbers or number not in passages:
            fail('Generated reading index source-number coverage is invalid.')
        indexed_numbers.add(number)
        item = load_json(CONTENT / str(entry['file']))
        expected = passages[number]
        if item.get('id') != expected['id']:
            fail(f'Generated reading ID drift at {number:03d}.')
        if item.get('sentences') != expected['sentences']:
            fail(f'Generated EN/TR body is not canonical CSV text at {number:03d}.')
        total_sentences += len(expected['sentences'])
        questions = item.get('enrichment', {}).get('questions')
        expected_questions = (
            builder.curated_questions(curated[number])
            if number <= 100 else derived[number]['questions']
        )
        if questions != expected_questions:
            fail(f'Generated questions drifted at {number:03d}.')
    if indexed_numbers != set(passages) or total_sentences != sentence_rows:
        fail('Generated reading index/body coverage does not match canonical CSV.')

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
        WORDS_SOURCE, PASSAGES_SOURCE, SENTENCES_SOURCE, QUESTIONS_SOURCE,
        CURATED_SOURCE, DICTIONARY_SOURCE, CONTENT / 'manifest.json',
    ):
        if not path.is_file():
            fail(f'Missing required source/content file: {path.relative_to(ROOT)}')
    words = validate_words()
    passages, sentence_rows, source_missing = canonical_readings()
    overlays = validate_no_sentence_overlay_sources()
    stale_references = validate_no_stale_reference()
    generated = validate_generated_content(passages, sentence_rows, source_missing)
    print(json.dumps({
        'words': words,
        'readings': {
            'records': len(passages),
            'canonicalSentenceRows': sentence_rows,
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
