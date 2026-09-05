#!/usr/bin/env python3
"""Build public PASSAGETR study modules from the canonical XLSX workbook."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import shutil
import sys
import xml.etree.ElementTree as ET
import zipfile
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterator


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import build_static_content as content  # noqa: E402


SOURCE_RELATIVE_PATH = Path(
    'source_data/canonical/study/PASSAGETR_YDS_Study_Canonical.xlsx'
)
DEFAULT_OUTPUT = ROOT / 'assets' / 'content' / 'study'
# The supplied workbook includes three valid study headwords that are not
# literal entries in the existing 7,500-word bank. These bindings preserve the
# source workbook while linking detail actions to the nearest canonical entry.
WORD_REF_ALIASES = {
    'threshold': 'boundary',
    'intermittent': 'episodic',
    'inevitably': 'necessarily',
}
SHEET_HEADERS = {
    '01_Modules': (
        'module_id', 'module_no', 'main_topic', 'subtopic', 'grammar_focus',
        'level_profile', 'status', 'source_file',
    ),
    '02_Words': (
        'word_id', 'module_id', 'order_no', 'word_ref', 'headword',
        'lexical_family_key', 'level', 'pos', 'meaning_tr', 'context_meaning',
        'yds_note', 'example_en', 'example_tr',
    ),
    '03_Word_Items': (
        'item_id', 'module_id', 'word_id', 'item_type', 'item_subtype',
        'item_order', 'value_en', 'value_tr', 'usage_note',
    ),
    '04_Sentences': (
        'sentence_id', 'module_id', 'order_no', 'level', 'sentence_en',
        'translation_tr', 'skeleton', 'main_subject', 'finite_verb',
        'object_complement', 'side_structures', 'verb_map', 'connector',
        'phrase_groups', 'reference_words', 'grammar_analysis', 'yds_note',
        'translation_strategy',
    ),
    '05_Readings': (
        'reading_id', 'module_id', 'title', 'text_en', 'main_idea_tr',
        'flow_analysis', 'important_words', 'connector_map',
        'reference_analysis',
    ),
    '06_Questions': (
        'question_id', 'module_id', 'section', 'question_type', 'order_no',
        'stem', 'correct_option', 'evidence', 'why_correct',
        'reminder_pattern',
    ),
    '07_Question_Options': (
        'option_id', 'question_id', 'module_id', 'option_letter',
        'option_text', 'is_correct', 'explanation',
    ),
    '08_Translations': (
        'translation_id', 'module_id', 'direction', 'order_no', 'source_text',
        'primary_translation', 'alternative_translation', 'skeleton_pattern',
        'key_words', 'grammar_note', 'translation_logic',
    ),
    '09_Structures': (
        'structure_id', 'module_id', 'category', 'order_no', 'expression',
        'meaning_tr', 'structure_pattern', 'example_en', 'confusion_note',
        'related_words', 'note',
    ),
    '10_Review': (
        'review_id', 'module_id', 'item_type', 'order_no', 'prompt_en',
        'prompt_tr', 'answer_en', 'answer_tr', 'note',
    ),
}


def clean(value: str | None) -> str:
    return content.clean(value)


def normalized(value: str | None) -> str:
    return content.normalized(value)


def source_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _tag_name(element: ET.Element) -> str:
    return element.tag.rsplit('}', 1)[-1]


def _column_index(reference: str | None) -> int:
    letters = ''.join(char for char in reference or '' if char.isalpha())
    value = 0
    for letter in letters.upper():
        value = value * 26 + ord(letter) - ord('A') + 1
    return value - 1


def _shared_strings(workbook: zipfile.ZipFile) -> list[str]:
    try:
        stream = workbook.open('xl/sharedStrings.xml')
    except KeyError:
        return []
    result: list[str] = []
    with stream:
        for _, element in ET.iterparse(stream, events=('end',)):
            if _tag_name(element) == 'si':
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
    if cell_type == 's':
        return shared[int(raw)] if raw else ''
    return raw


def _sheet_targets(workbook: zipfile.ZipFile) -> list[tuple[str, str]]:
    relationship_ns = (
        'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
    )
    with workbook.open('xl/_rels/workbook.xml.rels') as stream:
        relationships = ET.parse(stream).getroot()
    target_by_id = {
        element.attrib['Id']: element.attrib['Target'].lstrip('/')
        for element in relationships
        if _tag_name(element) == 'Relationship'
    }
    with workbook.open('xl/workbook.xml') as stream:
        workbook_xml = ET.parse(stream).getroot()
    targets: list[tuple[str, str]] = []
    for element in workbook_xml.iter():
        if _tag_name(element) != 'sheet':
            continue
        name = element.attrib['name']
        relationship_id = element.attrib[f'{{{relationship_ns}}}id']
        target = target_by_id[relationship_id]
        targets.append((name, target if target.startswith('xl/') else f'xl/{target}'))
    return targets


def iter_xlsx_rows(path: Path, sheet_name: str) -> Iterator[list[str]]:
    """Read a named XLSX worksheet using only the Python standard library."""
    with zipfile.ZipFile(path) as workbook:
        targets = dict(_sheet_targets(workbook))
        if sheet_name not in targets:
            raise ValueError(f'Canonical study workbook lacks sheet: {sheet_name}')
        shared = _shared_strings(workbook)
        with workbook.open(targets[sheet_name]) as stream:
            for _, element in ET.iterparse(stream, events=('end',)):
                if _tag_name(element) != 'row':
                    continue
                cells = [child for child in element if _tag_name(child) == 'c']
                width = max(
                    (_column_index(cell.attrib.get('r')) for cell in cells),
                    default=-1,
                ) + 1
                row = [''] * width
                for cell in cells:
                    row[_column_index(cell.attrib.get('r'))] = clean(
                        _cell_value(cell, shared)
                    )
                element.clear()
                yield row


def _records(path: Path, sheet_name: str) -> list[dict[str, str]]:
    rows = list(iter_xlsx_rows(path, sheet_name))
    if not rows:
        raise ValueError(f'Canonical study sheet is empty: {sheet_name}')
    expected = SHEET_HEADERS[sheet_name]
    headers = tuple(clean(value) for value in rows[0])
    if headers != expected:
        raise ValueError(
            f'Unexpected headers in {sheet_name}: expected {expected}, got {headers}'
        )
    records: list[dict[str, str]] = []
    for row_number, row in enumerate(rows[1:], start=2):
        padded = row + [''] * (len(headers) - len(row))
        if len(padded) != len(headers):
            raise ValueError(f'Too many values at {sheet_name} row {row_number}')
        record = {header: clean(padded[index]) for index, header in enumerate(headers)}
        if any(record.values()):
            records.append(record)
    return records


def load_workbook(path: Path) -> dict[str, list[dict[str, str]]]:
    if not path.is_file():
        raise FileNotFoundError(path)
    with zipfile.ZipFile(path) as workbook:
        names = [name for name, _ in _sheet_targets(workbook)]
    if names != list(SHEET_HEADERS):
        raise ValueError(
            'Study sheet order/schema mismatch: '
            f'expected {list(SHEET_HEADERS)}, got {names}'
        )
    return {name: _records(path, name) for name in SHEET_HEADERS}


def _require(record: dict[str, str], fields: tuple[str, ...], label: str) -> None:
    blank = [field for field in fields if not clean(record.get(field))]
    if blank:
        raise ValueError(f'Blank required values in {label}: {blank}')


def _sort(records: list[dict[str, str]], field: str = 'order_no') -> list[dict[str, str]]:
    if field == 'option_letter':
        return sorted(records, key=lambda record: record[field])
    try:
        return sorted(records, key=lambda record: int(record[field]))
    except ValueError as error:
        raise ValueError(f'Invalid numeric order field: {field}') from error


def _unique(records: list[dict[str, str]], field: str, label: str) -> None:
    values = [clean(record.get(field)) for record in records]
    if len(values) != len(set(values)):
        raise ValueError(f'Duplicate {field} in {label}')


def _canonical_word_refs() -> set[str]:
    path = ROOT / 'source_data' / 'canonical' / 'words' / content.WORDS_CANONICAL_FILENAME
    with path.open(encoding='utf-8-sig', newline='') as stream:
        return {
            normalized(row['en_word'])
            for row in csv.DictReader(stream, delimiter=';')
            if clean(row.get('en_word'))
        }


def resolved_word_ref(value: str) -> str:
    return WORD_REF_ALIASES.get(normalized(value), normalized(value))


def module_filename(module_id: str) -> str:
    return f"{module_id.replace('-', '_')}.json"


def _is_correct(value: str) -> bool:
    return normalized(value) in {'1', 'true', 'yes'}


def validate_workbook(workbook: dict[str, list[dict[str, str]]]) -> dict[str, Any]:
    modules = workbook['01_Modules']
    words = workbook['02_Words']
    word_items = workbook['03_Word_Items']
    sentences = workbook['04_Sentences']
    readings = workbook['05_Readings']
    questions = workbook['06_Questions']
    options = workbook['07_Question_Options']
    translations = workbook['08_Translations']
    structures = workbook['09_Structures']
    review = workbook['10_Review']
    if not modules:
        raise ValueError('Study workbook must have at least one module.')
    _unique(modules, 'module_id', '01_Modules')
    module_ids = {record['module_id'] for record in modules}
    for record in modules:
        _require(record, SHEET_HEADERS['01_Modules'], f"01_Modules/{record.get('module_id')}")
    for name, records, required in (
        ('02_Words', words, SHEET_HEADERS['02_Words']),
        ('04_Sentences', sentences, SHEET_HEADERS['04_Sentences']),
        (
            '06_Questions',
            questions,
            ('question_id', 'module_id', 'section', 'question_type', 'order_no',
             'stem', 'correct_option', 'why_correct'),
        ),
        (
            '07_Question_Options',
            options,
            ('option_id', 'question_id', 'module_id', 'option_letter',
             'option_text', 'is_correct'),
        ),
    ):
        for record in records:
            _require(record, required, f"{name}/{record.get(next(iter(record), 'row'))}")
    for record in readings:
        _require(
            record,
            tuple(field for field in SHEET_HEADERS['05_Readings'] if field != 'title'),
            f"05_Readings/{record.get('reading_id')}",
        )
    for record in translations:
        _require(
            record,
            ('translation_id', 'module_id', 'direction', 'order_no', 'source_text',
             'primary_translation', 'skeleton_pattern', 'key_words', 'grammar_note'),
            f"08_Translations/{record.get('translation_id')}",
        )
    for record in word_items:
        _require(
            record,
            ('item_id', 'module_id', 'word_id', 'item_type', 'item_order'),
            f"03_Word_Items/{record.get('item_id')}",
        )
        if not any(clean(record.get(field)) for field in ('value_en', 'value_tr', 'usage_note')):
            raise ValueError(f"Word item lacks content: {record['item_id']}")
    for record in structures:
        _require(
            record,
            ('structure_id', 'module_id', 'category', 'order_no', 'expression'),
            f"09_Structures/{record.get('structure_id')}",
        )
    for record in review:
        _require(
            record,
            ('review_id', 'module_id', 'item_type', 'order_no'),
            f"10_Review/{record.get('review_id')}",
        )
        if not any(clean(record.get(field)) for field in ('prompt_en', 'prompt_tr', 'answer_en', 'answer_tr')):
            raise ValueError(f"Review record lacks prompt/answer: {record['review_id']}")

    all_module_records = {
        '02_Words': words, '03_Word_Items': word_items, '04_Sentences': sentences,
        '05_Readings': readings, '06_Questions': questions,
        '07_Question_Options': options, '08_Translations': translations,
        '09_Structures': structures, '10_Review': review,
    }
    for name, records in all_module_records.items():
        for record in records:
            if record['module_id'] not in module_ids:
                raise ValueError(f'Orphan module relation in {name}: {record}')

    _unique(words, 'word_id', '02_Words')
    word_by_id = {record['word_id']: record for record in words}
    canonical_refs = _canonical_word_refs()
    question_by_id = {record['question_id']: record for record in questions}
    _unique(questions, 'question_id', '06_Questions')
    for record in word_items:
        word = word_by_id.get(record['word_id'])
        if word is None or word['module_id'] != record['module_id']:
            raise ValueError(f"Orphan word item: {record['item_id']}")
    for record in options:
        question = question_by_id.get(record['question_id'])
        if question is None or question['module_id'] != record['module_id']:
            raise ValueError(f"Orphan question option: {record['option_id']}")

    summary: dict[str, Any] = {'modules': len(modules), 'moduleChecks': []}
    for module in modules:
        module_id = module['module_id']
        module_words = _sort([item for item in words if item['module_id'] == module_id])
        module_sentences = _sort([item for item in sentences if item['module_id'] == module_id])
        module_readings = [item for item in readings if item['module_id'] == module_id]
        module_questions = [item for item in questions if item['module_id'] == module_id]
        module_translations = [item for item in translations if item['module_id'] == module_id]
        module_structures = [item for item in structures if item['module_id'] == module_id]
        module_review = [item for item in review if item['module_id'] == module_id]
        if len(module_words) != 15:
            raise ValueError(f'{module_id} must contain exactly 15 target words.')
        references = [resolved_word_ref(item['word_ref']) for item in module_words]
        if len(references) != len(set(references)):
            raise ValueError(f'{module_id} has duplicate target word_ref values.')
        missing_refs = sorted(set(references) - canonical_refs)
        if missing_refs:
            raise ValueError(f'{module_id} word_ref absent from canonical words: {missing_refs}')
        families = [normalized(item['lexical_family_key']) for item in module_words]
        if len(families) != len(set(families)):
            raise ValueError(f'{module_id} has duplicate lexical_family_key values.')
        if len(module_sentences) != 5 or len(module_readings) != 1:
            raise ValueError(f'{module_id} requires 5 sentences and 1 reading.')
        reading_questions = [item for item in module_questions if item['section'] == 'reading']
        test_questions = [item for item in module_questions if item['section'] == 'mixed_test']
        if len(reading_questions) != 5 or len(test_questions) != 10:
            raise ValueError(f'{module_id} requires 5 reading and 10 mixed-test questions.')
        if len(module_questions) != 15:
            raise ValueError(f'{module_id} has an unsupported question section.')
        for question in module_questions:
            question_options = _sort(
                [option for option in options if option['question_id'] == question['question_id']],
                'option_letter',
            )
            letters = {option['option_letter'] for option in question_options}
            correct = [option for option in question_options if _is_correct(option['is_correct'])]
            if letters != {'A', 'B', 'C', 'D', 'E'} or len(correct) != 1:
                raise ValueError(f"{question['question_id']} must have A-E and one correct option.")
            if correct[0]['option_letter'] != question['correct_option']:
                raise ValueError(f"Correct option mismatch in {question['question_id']}.")
        direction_counts = Counter(item['direction'] for item in module_translations)
        if direction_counts != Counter({'EN_TR': 7, 'TR_EN': 7}):
            raise ValueError(f'{module_id} requires 7 EN_TR and 7 TR_EN translations.')
        review_counts = Counter(item['item_type'] for item in module_review)
        expected_review = Counter({
            'critical_word': 10, 'critical_pattern': 5, 'grammar_summary': 3,
            'yds_trap': 1, 'active_recall_en': 5, 'active_recall_tr': 5,
        })
        if review_counts != expected_review:
            raise ValueError(f'{module_id} review contract is incomplete.')
        summary['moduleChecks'].append({
            'moduleId': module_id, 'words': len(module_words),
            'lexicalFamilies': len(set(families)), 'sentences': len(module_sentences),
            'readings': len(module_readings), 'readingQuestions': len(reading_questions),
            'translations': dict(direction_counts), 'testQuestions': len(test_questions),
            'structures': len(module_structures), 'reviewItems': len(module_review),
            'manualWordRefBindings': sum(
                normalized(item['word_ref']) != resolved_word_ref(item['word_ref'])
                for item in module_words
            ),
        })
    return summary


def _question_payload(
    question: dict[str, str], options: list[dict[str, str]],
) -> dict[str, Any]:
    return {**question, 'options': _sort(options, 'option_letter')}


def build_payloads(
    workbook: dict[str, list[dict[str, str]]], source: Path,
) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    summary = validate_workbook(workbook)
    options_by_question: dict[str, list[dict[str, str]]] = defaultdict(list)
    for option in workbook['07_Question_Options']:
        options_by_question[option['question_id']].append(option)
    payloads: dict[str, dict[str, Any]] = {}
    for module in _sort(workbook['01_Modules'], 'module_no'):
        module_id = module['module_id']
        module_words = _sort([
            item for item in workbook['02_Words'] if item['module_id'] == module_id
        ])
        word_items_by_word: dict[str, list[dict[str, str]]] = defaultdict(list)
        for item in workbook['03_Word_Items']:
            if item['module_id'] == module_id:
                word_items_by_word[item['word_id']].append(item)
        words = [
            {
                **word,
                'source_word_ref': word['word_ref'],
                'word_ref': resolved_word_ref(word['word_ref']),
                'items': _sort(word_items_by_word[word['word_id']], 'item_order'),
            }
            for word in module_words
        ]
        questions = [
            _question_payload(question, options_by_question[question['question_id']])
            for question in _sort([
                item for item in workbook['06_Questions'] if item['module_id'] == module_id
            ])
        ]
        reading_questions = [item for item in questions if item['section'] == 'reading']
        test_questions = [item for item in questions if item['section'] == 'mixed_test']
        reading = next(item for item in workbook['05_Readings'] if item['module_id'] == module_id)
        counts = {
            'words': len(words),
            'sentences': len([
                item for item in workbook['04_Sentences']
                if item['module_id'] == module_id
            ]),
            'readings': 1,
            'translations': len([
                item for item in workbook['08_Translations']
                if item['module_id'] == module_id
            ]),
            'testQuestions': len(test_questions),
        }
        payloads[module_id] = {
            'schemaVersion': 1,
            'module': {
                **module,
                'file': f"modules/{module_filename(module_id)}",
                'counts': counts,
            },
            'words': words,
            'sentences': _sort([
                item for item in workbook['04_Sentences'] if item['module_id'] == module_id
            ]),
            'reading': {**reading, 'questions': reading_questions},
            'translations': {
                'enTr': _sort([
                    item for item in workbook['08_Translations']
                    if item['module_id'] == module_id and item['direction'] == 'EN_TR'
                ]),
                'trEn': _sort([
                    item for item in workbook['08_Translations']
                    if item['module_id'] == module_id and item['direction'] == 'TR_EN'
                ]),
            },
            'structures': _sort([
                item for item in workbook['09_Structures'] if item['module_id'] == module_id
            ]),
            'testQuestions': test_questions,
            'review': _sort([
                item for item in workbook['10_Review'] if item['module_id'] == module_id
            ]),
        }
    module_index = []
    for module in _sort(workbook['01_Modules'], 'module_no'):
        payload = payloads[module['module_id']]
        module_index.append({
            **module,
            'file': f"modules/{module_filename(module['module_id'])}",
            'counts': payload['module']['counts'],
        })
    manifest = {
        'schemaVersion': 1,
        'source': str(source.relative_to(ROOT)).replace('\\', '/'),
        'checksums': {'canonicalStudy': source_hash(source)},
        'counts': {
            'modules': len(module_index),
            'words': sum(len(payload['words']) for payload in payloads.values()),
            'sentences': sum(len(payload['sentences']) for payload in payloads.values()),
            'readings': len(module_index),
        },
        'modules': module_index,
        'validation': summary,
    }
    return manifest, payloads


def _write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, separators=(',', ':')),
        encoding='utf-8',
    )


def build(source: Path, output: Path) -> dict[str, Any]:
    workbook = load_workbook(source)
    manifest, payloads = build_payloads(workbook, source)
    if output.exists():
        shutil.rmtree(output)
    _write_json(output / 'study_manifest.json', manifest)
    for module_id, payload in payloads.items():
        _write_json(output / 'modules' / module_filename(module_id), payload)
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, default=ROOT / SOURCE_RELATIVE_PATH)
    parser.add_argument('--output', type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    manifest = build(args.source.resolve(), args.output.resolve())
    print(json.dumps({
        'modules': manifest['counts']['modules'],
        'words': manifest['counts']['words'],
        'sentences': manifest['counts']['sentences'],
        'readings': manifest['counts']['readings'],
        'source': manifest['source'],
    }, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, ET.ParseError, zipfile.BadZipFile) as error:
        print(f'STUDY_BUILD_ERROR: {error}', file=sys.stderr)
        raise SystemExit(1)
