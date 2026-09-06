#!/usr/bin/env python3
"""Validate generated Testler assets against the canonical Test Bank workbook."""

from __future__ import annotations

import hashlib
import json
import sys
import zipfile
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import build_test_content as builder  # noqa: E402
import build_static_content as static  # noqa: E402


SOURCE = ROOT / 'source_data' / 'canonical' / 'tests' / 'passagetr_test_bank.xlsx'
OUTPUT = ROOT / 'assets' / 'content' / 'tests'


def fail(message: str) -> None:
    raise ValueError(message)


def load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(value, dict):
        fail(f'JSON object expected: {path.relative_to(ROOT)}')
    return value


def source_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    if not SOURCE.is_file():
        fail('Canonical Test Bank workbook is missing.')
    if list(SOURCE.parent.glob('*.xlsx')) != [SOURCE]:
        fail('Tests canonical directory must contain only passagetr_test_bank.xlsx.')
    sheets = builder.read_workbook(SOURCE)
    builder._require_schema(sheets)
    manifest = load_json(OUTPUT / 'test_bank_manifest.json')
    if manifest.get('canonicalSource') != 'canonical/tests/passagetr_test_bank.xlsx':
        fail('Manifest canonical Test Bank source is invalid.')
    if manifest.get('sourceHash') != source_hash(SOURCE):
        fail('Manifest Test Bank checksum is invalid.')
    words = sheets['words']
    structures = sheets['phrasal_prepositions']
    exam_rows = sheets['vocabulary_tests']
    expected_counts = {
        'modules': 110,
        'wordRows': len(words),
        'uniqueHeadwords': len({static.normalize_dictionary_key(row['en_word']) for row in words}),
        'structures': len(structures),
        'structureCategories': len({row['category'] for row in structures}),
        'exams': 9,
        'questions': len(exam_rows),
        'options': len(exam_rows) * 5,
    }
    counts = manifest.get('counts')
    if not isinstance(counts, dict) or any(counts.get(key) != value for key, value in expected_counts.items()):
        fail(f'Manifest Testler counts are invalid: {counts!r}')
    modules = manifest.get('modules')
    if not isinstance(modules, list) or len(modules) != 110:
        fail('Generated Testler module index is invalid.')
    canonical_modules: dict[int, list[dict[str, str]]] = {number: [] for number in range(1, 111)}
    for row in words:
        canonical_modules[int(row['day'])].append(row)
    generated_word_rows = 0
    for summary in modules:
        number = int(summary.get('moduleNo', 0))
        if number not in canonical_modules or summary.get('file') != f'modules/module_{number:03d}.json':
            fail('Generated Testler module summary is invalid.')
        payload = load_json(OUTPUT / str(summary['file']))
        generated = payload.get('words')
        expected = canonical_modules[number]
        if not isinstance(generated, list) or len(generated) != len(expected):
            fail(f'Module {number:03d} lost or added a canonical word row.')
        for generated_row, canonical_row in zip(generated, expected):
            expected_fields = {
                'headword': canonical_row['en_word'],
                'meaningTr': canonical_row['tr_meaning'],
                'pos': canonical_row['pos'],
                'exampleEn': canonical_row['example_en'],
                'exampleTr': canonical_row['example_tr'],
                'synonymsRaw': canonical_row['synonyms_raw'] or None,
            }
            if any(generated_row.get(key) != value for key, value in expected_fields.items()):
                fail(f'Module {number:03d} word content drifted from the Test Bank.')
        generated_word_rows += len(generated)
    if generated_word_rows != len(words):
        fail('Generated modules do not preserve every Test Bank word row.')
    structures_payload = load_json(OUTPUT / 'structures.json')
    generated_structures = structures_payload.get('structures')
    if not isinstance(generated_structures, list) or len(generated_structures) != len(structures):
        fail('Generated structures are incomplete.')
    for generated, canonical in zip(generated_structures, structures):
        if any(generated.get(key) != value for key, value in {
            'category': canonical['category'],
            'structure': canonical['structure'],
            'meaningTr': canonical['tr_meaning'],
            'exampleEn': canonical['example_en'] or None,
            'exampleTr': canonical['example_tr'] or None,
        }.items()):
            fail('Generated structure content drifted from the Test Bank.')
    exams = manifest.get('exams')
    if not isinstance(exams, list) or len(exams) != 9:
        fail('Generated Testler exam index is invalid.')
    source_questions = {(int(row['test_no']), int(row['question_no'])): row for row in exam_rows}
    generated_questions = 0
    missing_option_translations = 0
    for summary in exams:
        test_no = int(summary.get('testNo', 0))
        payload = load_json(OUTPUT / str(summary.get('file', '')))
        questions = payload.get('questions')
        if test_no not in range(1, 10) or not isinstance(questions, list) or len(questions) != 50:
            fail('Generated Testler exam payload is invalid.')
        for question in questions:
            source_row = source_questions.get((test_no, int(question.get('number', 0))))
            if source_row is None or question.get('question') != source_row['question_sentence']:
                fail('Generated question text drifted from the Test Bank.')
            options = question.get('options')
            if not isinstance(options, list) or len(options) != 5:
                fail('Generated question lacks A–E options.')
            expected_options = [source_row[f'option_{letter}'] for letter in 'abcde']
            if [item.get('textEn') for item in options] != expected_options:
                fail('Generated English options drifted from the Test Bank.')
            if question.get('correctAnswer') != source_row['correct_answer']:
                fail('Generated correct answer drifted from the Test Bank.')
            if static.normalize_dictionary_key(question['correctAnswer']) not in {
                static.normalize_dictionary_key(item['textEn']) for item in options
            }:
                fail('Generated correct answer is not among the canonical options.')
            for option in options:
                translation = option.get('textTr')
                source = option.get('translationSource')
                if translation is None:
                    missing_option_translations += 1
                    if source is not None:
                        fail('Missing option Turkish meaning has a lookup source.')
                elif source not in {
                    'test_bank_words', 'canonical_words', 'canonical_dictionary',
                }:
                    fail('Option Turkish meaning has an invalid lookup source.')
            generated_questions += 1
    if generated_questions != len(exam_rows):
        fail('Generated Testler question count is invalid.')
    if counts.get('optionTrMissing') != missing_option_translations or counts.get('optionTrCovered') != counts['options'] - missing_option_translations:
        fail('Option Turkish coverage counts are invalid.')
    print(json.dumps({
        'testValidator': 'PASS',
        'canonicalSource': manifest['canonicalSource'],
        'modules': counts['modules'],
        'wordRows': counts['wordRows'],
        'uniqueHeadwords': counts['uniqueHeadwords'],
        'structures': counts['structures'],
        'exams': counts['exams'],
        'questions': counts['questions'],
        'options': counts['options'],
        'optionTrCovered': counts['optionTrCovered'],
        'optionTrMissing': counts['optionTrMissing'],
    }, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError, zipfile.BadZipFile) as error:  # type: ignore[name-defined]
        print(f'TEST_CONTENT_VALIDATION_ERROR: {error}', file=sys.stderr)
        raise SystemExit(1)
