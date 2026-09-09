#!/usr/bin/env python3
"""Build the public Testler assets from the canonical Test Bank workbook.

The workbook is the sole authority for Testler modules, structures, exam
questions, English options, and correct answers.  Turkish option labels are a
generated display enrichment: Test Bank words, then the public 9,000-word
bank, then the public dictionary are consulted read-only in that order.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import shutil
import sys
import xml.etree.ElementTree as ET
import zipfile
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterator


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import build_static_content as static  # noqa: E402


SOURCE = ROOT / 'source_data'
TEST_CANONICAL_RELATIVE_PATH = 'canonical/tests/passagetr_test_bank_CANONICAL_v4.xlsx'
TEST_SOURCE = SOURCE / TEST_CANONICAL_RELATIVE_PATH
WORDS_SOURCE = SOURCE / 'canonical' / 'words' / static.WORDS_CANONICAL_FILENAME
DICTIONARY_SOURCE = SOURCE / 'canonical' / 'dictionary' / 'dictionary_tr_en.xlsx'
OUTPUT = ROOT / 'assets' / 'content' / 'tests'
REQUIRED_SHEETS = ('words', 'phrasal_prepositions', 'vocabulary_tests')
WORD_FIELDS = (
    'day', 'en_word', 'tr_meaning', 'pos', 'example_en', 'example_tr',
    'synonyms_raw',
)
REQUIRED_WORD_FIELDS = tuple(field for field in WORD_FIELDS if field != 'synonyms_raw')
STRUCTURE_FIELDS = ('category', 'structure', 'tr_meaning', 'example_en', 'example_tr')
EXAM_FIELDS = (
    'test_no', 'question_no', 'question_sentence', 'question_sentence_tr',
    'option_a', 'option_b', 'option_c', 'option_d', 'option_e',
    'correct_answer',
)
EXPECTED_MODULES = 150
WORDS_PER_MODULE = 20
EXPECTED_WORD_ROWS = EXPECTED_MODULES * WORDS_PER_MODULE
EXPECTED_EXAMS = 20
QUESTIONS_PER_EXAM = 50
EXPECTED_EXAM_QUESTIONS = EXPECTED_EXAMS * QUESTIONS_PER_EXAM


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
                result.append(''.join(
                    node.text or '' for node in element.iter()
                    if _tag_name(node) == 't'
                ))
                element.clear()
    return result


def _cell_value(cell: ET.Element, shared: list[str]) -> str:
    cell_type = cell.attrib.get('t')
    if cell_type == 'inlineStr':
        return ''.join(
            node.text or '' for node in cell.iter() if _tag_name(node) == 't'
        )
    raw = next((node.text or '' for node in cell if _tag_name(node) == 'v'), '')
    return shared[int(raw)] if cell_type == 's' and raw else raw


def _sheet_target(target: str) -> str:
    target = target.lstrip('/')
    return target if target.startswith('xl/') else f'xl/{target}'


def _sheet_rows(workbook: zipfile.ZipFile, path: str, shared: list[str]) -> Iterator[list[str]]:
    with workbook.open(path) as stream:
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


def read_workbook(path: Path) -> dict[str, list[dict[str, str]]]:
    """Read every Test Bank worksheet with the standard library only."""
    with zipfile.ZipFile(path) as workbook:
        shared = _shared_strings(workbook)
        document = ET.fromstring(workbook.read('xl/workbook.xml'))
        relationships = ET.fromstring(workbook.read('xl/_rels/workbook.xml.rels'))
        targets = {
            item.attrib['Id']: _sheet_target(item.attrib['Target'])
            for item in relationships
        }
        relation_key = '{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id'
        result: dict[str, list[dict[str, str]]] = {}
        sheets = document.find('{http://schemas.openxmlformats.org/spreadsheetml/2006/main}sheets')
        if sheets is None:
            raise ValueError('Test Bank workbook has no sheets.')
        for sheet in sheets:
            name = static.clean(sheet.attrib.get('name'))
            target = targets.get(sheet.attrib.get(relation_key, ''))
            if not name or not target:
                raise ValueError('Test Bank workbook has an invalid sheet relationship.')
            rows = list(_sheet_rows(workbook, target, shared))
            if not rows:
                result[name] = []
                continue
            width = max(len(row) for row in rows)
            normalized_rows = [row + [''] * (width - len(row)) for row in rows]
            headers = [static.clean(value) for value in normalized_rows[0]]
            if not all(headers) or len(headers) != len(set(headers)):
                raise ValueError(f'Invalid headers in Test Bank sheet {name!r}.')
            result[name] = [
                {
                    header: static.clean(row[index])
                    for index, header in enumerate(headers)
                }
                for row in normalized_rows[1:]
            ]
    return result


def _require_schema(sheets: dict[str, list[dict[str, str]]]) -> None:
    if tuple(sheets) != REQUIRED_SHEETS:
        raise ValueError(
            f'Test Bank sheets must be exactly {REQUIRED_SHEETS}, got {tuple(sheets)}.'
        )
    expected = {
        'words': set(WORD_FIELDS),
        'phrasal_prepositions': set(STRUCTURE_FIELDS),
        'vocabulary_tests': set(EXAM_FIELDS),
    }
    for name, fields in expected.items():
        rows = sheets[name]
        if not rows or set(rows[0]) != fields:
            raise ValueError(f'Test Bank schema mismatch in {name!r}.')


def _integer(value: str, label: str) -> int:
    try:
        result = int(static.clean(value))
    except ValueError as error:
        raise ValueError(f'Invalid {label}: {value!r}') from error
    if result < 1:
        raise ValueError(f'Invalid {label}: {value!r}')
    return result


def _source_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _json_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, separators=(',', ':')).encode('utf-8')


def _write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(_json_bytes(value))


def _lookup_from_test_words(rows: list[dict[str, str]]) -> dict[str, str]:
    # Workbook row order makes ties deterministic without altering the source.
    result: dict[str, str] = {}
    for row in rows:
        key = static.normalize_dictionary_key(row['en_word'])
        meaning = static.clean(row['tr_meaning'])
        if key and meaning and key not in result:
            result[key] = meaning
    return result


def _lookup_from_canonical_words() -> dict[str, str]:
    result: dict[str, str] = {}
    for row in static.read_csv(WORDS_SOURCE):
        key = static.normalize_dictionary_key(row.get('en_word'))
        meaning = static.clean(row.get('tr_meaning'))
        if key and meaning and key not in result:
            result[key] = meaning
    return result


def _lookup_from_dictionary() -> dict[str, str]:
    rows = static.iter_xlsx_rows(DICTIONARY_SOURCE)
    try:
        header = next(rows)
    except StopIteration as error:
        raise ValueError('Canonical dictionary workbook is empty.') from error
    index = {static.normalized(value): position for position, value in enumerate(header)}
    required = ('en_word', 'tr_meaning_clean')
    if any(field not in index for field in required):
        raise ValueError('Canonical dictionary workbook has an invalid schema.')
    result: dict[str, str] = {}
    for row in rows:
        english = row[index['en_word']] if index['en_word'] < len(row) else ''
        meaning = row[index['tr_meaning_clean']] if index['tr_meaning_clean'] < len(row) else ''
        key = static.normalize_dictionary_key(english)
        meaning = static.clean(meaning)
        if key and meaning and key not in result:
            result[key] = meaning
    return result


def _option_translation(
    option: str,
    test_words: dict[str, str],
    canonical_words: dict[str, str],
    dictionary: dict[str, str],
) -> tuple[str | None, str | None]:
    key = static.normalize_dictionary_key(option)
    for source, lookup in (
        ('test_bank_words', test_words),
        ('canonical_words', canonical_words),
        ('canonical_dictionary', dictionary),
    ):
        value = lookup.get(key)
        if value:
            return value, source
    return None, None


def _question_fingerprint(question: dict[str, Any]) -> str:
    # The Turkish question translation is display-only.  Keeping the
    # fingerprint tied to scored EN content preserves valid answers when a
    # future canonical revision improves only a translation.
    canonical = {
        'id': question['id'],
        'number': question['number'],
        'question': question['question'],
        'options': [item['textEn'] for item in question['options']],
        'correctAnswer': question['correctAnswer'],
    }
    return hashlib.sha256(_json_bytes(canonical)).hexdigest()


def build(
    source: Path = TEST_SOURCE,
    output: Path = OUTPUT,
) -> dict[str, Any]:
    for path in (source, WORDS_SOURCE, DICTIONARY_SOURCE):
        if not path.is_file():
            raise FileNotFoundError(path)
    sheets = read_workbook(source)
    _require_schema(sheets)
    words = sheets['words']
    structures = sheets['phrasal_prepositions']
    exam_rows = sheets['vocabulary_tests']
    for row_number, row in enumerate(words, start=2):
        if any(not static.clean(row[field]) for field in REQUIRED_WORD_FIELDS):
            raise ValueError(f'Blank Test Bank word field at row {row_number}.')
    for row_number, row in enumerate(structures, start=2):
        if any(not static.clean(row[field]) for field in ('category', 'structure', 'tr_meaning')):
            raise ValueError(f'Blank Test Bank structure field at row {row_number}.')
    for row_number, row in enumerate(exam_rows, start=2):
        if any(not static.clean(row[field]) for field in EXAM_FIELDS):
            raise ValueError(f'Blank Test Bank exam field at row {row_number}.')

    test_words = _lookup_from_test_words(words)
    canonical_words = _lookup_from_canonical_words()
    dictionary = _lookup_from_dictionary()
    module_words: dict[int, list[dict[str, Any]]] = defaultdict(list)
    for row in words:
        number = _integer(row['day'], 'module number')
        order = len(module_words[number]) + 1
        module_words[number].append({
            'id': f'test-module-{number:03d}-word-{order:02d}',
            'order': order,
            'headword': row['en_word'],
            'meaningTr': row['tr_meaning'],
            'pos': row['pos'],
            'exampleEn': row['example_en'],
            'exampleTr': row['example_tr'],
            'synonymsRaw': row['synonyms_raw'] or None,
        })
    module_numbers = sorted(module_words)
    if module_numbers != list(range(1, EXPECTED_MODULES + 1)) or any(
        len(module_words[number]) != WORDS_PER_MODULE for number in module_numbers
    ):
        raise ValueError(
            f'Test Bank modules must be 001–{EXPECTED_MODULES:03d} '
            f'with {WORDS_PER_MODULE} word rows each.'
        )
    unique_headwords = {
        static.normalize_dictionary_key(row['en_word']) for row in words
    }
    if len(words) != EXPECTED_WORD_ROWS or len(unique_headwords) != EXPECTED_WORD_ROWS:
        raise ValueError(
            f'Test Bank must contain {EXPECTED_WORD_ROWS} unique word rows.'
        )

    generated_files: list[str] = []
    if output.exists():
        shutil.rmtree(output)
    modules: list[dict[str, Any]] = []
    for number in module_numbers:
        file_name = f'modules/module_{number:03d}.json'
        payload = {
            'moduleNo': number,
            'words': module_words[number],
        }
        _write_json(output / file_name, payload)
        generated_files.append(file_name)
        modules.append({
            'id': f'test-module-{number:03d}',
            'moduleNo': number,
            'wordCount': len(module_words[number]),
            'file': file_name,
        })

    structures_payload = {
        'categories': sorted({row['category'] for row in structures}),
        'structures': [
            {
                'id': f'structure-{index:04d}',
                'category': row['category'],
                'structure': row['structure'],
                'meaningTr': row['tr_meaning'],
                'exampleEn': row['example_en'] or None,
                'exampleTr': row['example_tr'] or None,
            }
            for index, row in enumerate(structures, start=1)
        ],
    }
    _write_json(output / 'structures.json', structures_payload)
    generated_files.append('structures.json')

    exams: dict[int, list[dict[str, Any]]] = defaultdict(list)
    translation_sources: Counter[str] = Counter()
    missing_options: list[dict[str, Any]] = []
    fingerprints: dict[str, str] = {}
    for row in exam_rows:
        test_no = _integer(row['test_no'], 'test number')
        question_no = _integer(row['question_no'], 'question number')
        options: list[dict[str, Any]] = []
        for letter in 'abcde':
            english = row[f'option_{letter}']
            meaning, lookup_source = _option_translation(
                english, test_words, canonical_words, dictionary,
            )
            if lookup_source:
                translation_sources[lookup_source] += 1
            else:
                missing_options.append({
                    'testNo': test_no,
                    'questionNo': question_no,
                    'option': letter.upper(),
                    'textEn': english,
                })
            options.append({
                'key': letter.upper(),
                'textEn': english,
                'textTr': meaning,
                'translationSource': lookup_source,
            })
        correct = row['correct_answer']
        if static.normalize_dictionary_key(correct) not in {
            static.normalize_dictionary_key(item['textEn']) for item in options
        }:
            raise ValueError(
                f'Correct answer does not match an option: Test {test_no}, question {question_no}.'
            )
        question = {
            'id': f'test-{test_no:02d}-q-{question_no:03d}',
            'number': question_no,
            'question': row['question_sentence'],
            'questionTr': row['question_sentence_tr'],
            'options': options,
            'correctAnswer': correct,
        }
        question['fingerprint'] = _question_fingerprint(question)
        fingerprints[question['id']] = question['fingerprint']
        exams[test_no].append(question)
    test_numbers = sorted(exams)
    if test_numbers != list(range(1, EXPECTED_EXAMS + 1)) or any(
        [item['number'] for item in exams[number]]
        != list(range(1, QUESTIONS_PER_EXAM + 1))
        for number in test_numbers
    ):
        raise ValueError(
            f'Test Bank must contain Test 1–{EXPECTED_EXAMS} with '
            f'questions 1–{QUESTIONS_PER_EXAM}.'
        )
    exam_summaries: list[dict[str, Any]] = []
    for number in test_numbers:
        file_name = f'exams/test_{number:02d}.json'
        payload = {'testNo': number, 'questions': exams[number]}
        _write_json(output / file_name, payload)
        generated_files.append(file_name)
        exam_summaries.append({
            'testNo': number,
            'questionCount': len(exams[number]),
            'file': file_name,
        })
    source_hash = _source_hash(source)
    manifest = {
        'schemaVersion': 1,
        'canonicalSource': TEST_CANONICAL_RELATIVE_PATH,
        'sourceHash': source_hash,
        'lookupSources': {
            'testBankWords': f'{TEST_CANONICAL_RELATIVE_PATH}#words',
            'canonicalWords': f'canonical/words/{static.WORDS_CANONICAL_FILENAME}',
            'canonicalDictionary': 'canonical/dictionary/dictionary_tr_en.xlsx',
        },
        'counts': {
            'modules': len(modules),
            'wordRows': len(words),
            'uniqueHeadwords': len(unique_headwords),
            'structures': len(structures),
            'structureCategories': len(structures_payload['categories']),
            'exams': len(exam_summaries),
            'questions': len(exam_rows),
            'options': len(exam_rows) * 5,
            'questionTrCovered': sum(
                bool(static.clean(row['question_sentence_tr']))
                for row in exam_rows
            ),
            'questionTrMissing': sum(
                not static.clean(row['question_sentence_tr'])
                for row in exam_rows
            ),
            'optionTrCovered': len(exam_rows) * 5 - len(missing_options),
            'optionTrMissing': len(missing_options),
        },
        'optionTranslationSources': dict(sorted(translation_sources.items())),
        'optionTranslationMissing': missing_options,
        'modules': modules,
        'structuresFile': 'structures.json',
        'exams': exam_summaries,
        'questionContent': {
            'version': source_hash,
            'fingerprints': fingerprints,
        },
        'generatedFiles': ['test_bank_manifest.json', *generated_files],
    }
    _write_json(output / 'test_bank_manifest.json', manifest)
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, default=TEST_SOURCE)
    parser.add_argument('--output', type=Path, default=OUTPUT)
    args = parser.parse_args()
    manifest = build(source=args.source, output=args.output)
    print(json.dumps({
        'modules': manifest['counts']['modules'],
        'wordRows': manifest['counts']['wordRows'],
        'structures': manifest['counts']['structures'],
        'exams': manifest['counts']['exams'],
        'questions': manifest['counts']['questions'],
        'questionTrCovered': manifest['counts']['questionTrCovered'],
        'questionTrMissing': manifest['counts']['questionTrMissing'],
        'options': manifest['counts']['options'],
        'optionTrMissing': manifest['counts']['optionTrMissing'],
        'source': manifest['canonicalSource'],
    }, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError, zipfile.BadZipFile) as error:
        print(f'TEST_CONTENT_BUILD_ERROR: {error}', file=sys.stderr)
        raise SystemExit(1)
