#!/usr/bin/env python3
"""Build PASSAGETR public content from its canonical static sources.

Words are read only from the 9,000-record canonical CSV.  Reading EN/TR body
and questions are read only from the canonical 800-reading Excel workbook;
no repair, translation, or editorial JSON overlay participates in production
builds.
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
    'phrase': 'phrase',
}
POS_ORDER = ('prep.', 'phr. v.', 'phrase', 'v.', 'n.', 'adj.', 'adv.', 'NP', 'conj.', 'det.', 'modal')
WORD_TOKEN = re.compile(r"[A-Za-z]+(?:['-][A-Za-z]+)*")
CANONICAL_WORD_TAG = re.compile(
    r'[a-z0-9]+(?: [a-z0-9]+)*(?: & [a-z0-9]+(?: [a-z0-9]+)*)*'
)
CANONICAL_LEVELS = ('A1', 'A2', 'B1', 'B2', 'C1', 'C2')
# Legacy word-level variants seen in source data map onto the canonical CEFR
# ladder; anything else fails the build instead of being silently invented.
WORD_LEVEL_NORMALIZATION = {
    'A1+': 'A1', 'A2+': 'A2', 'B1+': 'B1', 'B2+': 'B2', 'C1+': 'C1',
    'A1/A2': 'A2', 'A2/B1': 'B1', 'B1/B2': 'B2', 'B1+/B2': 'B2',
    'B2/C1': 'C1', 'C1/C2': 'C2',
}
READINGS_CANONICAL_FILENAME = 'PASSAGETR_READINGS_CANONICAL_800_FINAL.xlsx'
READINGS_LEGACY_MAP_RELATIVE_PATH = Path('mappings/reading_legacy_ids_001_678.json')
EXPECTED_READINGS = 800
EXPECTED_SENTENCES = 7500
EXPECTED_QUESTIONS = 4000
EXPECTED_QUESTIONS_PER_READING = 5
EXPECTED_READING_SENTENCES_MIN = 6
EXPECTED_READING_SENTENCES_MAX = 12
MIN_SENTENCE_ENGLISH_WORDS = 10
READING_QUESTION_TYPES = (
    'main_idea', 'detail', 'relationship_analysis', 'inference',
    'author_purpose',
)
READING_QUESTION_TYPE_LABELS = READING_QUESTION_TYPES
READING_PACK_NAME = 'PASSAGETR Readings Canonical 800'
CORRECT_OPTION_INDEX = {'A': 0, 'B': 1, 'C': 2, 'D': 3}
EVIDENCE_RANGE = re.compile(r'^\s*(\d+)\s*-\s*(\d+)\s*$')
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
WORDS_CANONICAL_FILENAME = 'passagetr_yds_words_canonical_9000_FINAL_v2.csv'
INVALID_SPREADSHEET_TOKENS = (
    '#AD?', '#NAME?', '#N/A', '#VALUE!', '#REF!', '#DIV/0!', '#NUM!', '#NULL!',
    '#YOK', '#YOK?', '#DE\u011eER!', '#BA\u015eV!', '#SAYI!', '#B\u00d6L/0!',
)
GENERIC_FOCUS_WORDS = frozenset({
    'because', 'different', 'good', 'idea', 'people', 'place', 'problem',
    'thing', 'things', 'time', 'topic', 'way', 'work', 'world', 'year',
})

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
    return deterministic_id(
        'word', f'passagetr canonical 9000|{normalized(word)}|{normalized(pos)}'
    )


def canonical_level(raw: str | None, *, kind: str, where: str) -> str:
    """Normalize a source level onto the canonical A1–C2 ladder or fail."""
    value = clean(raw)
    if value in CANONICAL_LEVELS:
        return value
    mapped = WORD_LEVEL_NORMALIZATION.get(value)
    if mapped is not None:
        return mapped
    raise ValueError(f'Invalid {kind} level at {where}: {raw!r}')


def passage_id(title: str) -> str:
    return deterministic_id('passage', title)


def reading_id(number: int) -> str:
    """Stable runtime ID derived only from the source number."""
    return deterministic_id('reading', f'{number:03d}')


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


def is_canonical_word_tag(value: str) -> bool:
    """Return whether a word tag uses the public canonical taxonomy form."""
    return CANONICAL_WORD_TAG.fullmatch(value) is not None


def english_tokens(value: str) -> list[str]:
    """Return normalized English tokens without changing the source text."""
    return [normalize_dictionary_key(match.group(0)) for match in WORD_TOKEN.finditer(value)]


def load_json_object(path: Path, label: str) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding='utf-8'))
    except json.JSONDecodeError as error:
        raise ValueError(f'Invalid {label}: {path}') from error
    if not isinstance(payload, dict):
        raise ValueError(f'{label} must be a JSON object.')
    return payload


def read_xlsx_sheet(path: Path, sheet_name: str) -> list[list[str]]:
    """Read a named XLSX worksheet using only the standard library.

    Resolves the sheet name through workbook relationships instead of
    assuming it is the first worksheet.
    """
    with zipfile.ZipFile(path) as workbook:
        workbook_root = ET.fromstring(workbook.read('xl/workbook.xml'))
        namespaces = {
            'main': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main',
            'rel': 'http://schemas.openxmlformats.org/officeDocument/2006/relationships',
        }
        target: str | None = None
        for sheet in workbook_root.findall('main:sheets/main:sheet', namespaces):
            if sheet.get('name') == sheet_name:
                relationship = sheet.get('{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id')
                relationships = ET.fromstring(workbook.read('xl/_rels/workbook.xml.rels'))
                for item in relationships:
                    if item.get('Id') == relationship:
                        target = (item.get('Target') or '').lstrip('/')
                        break
        if target is None:
            raise ValueError(f'Workbook lacks sheet {sheet_name!r}: {path}')
        if not target.startswith('xl/'):
            target = f'xl/{target}'
        shared = _shared_strings(workbook)
        with workbook.open(target) as stream:
            rows: list[list[str]] = []
            for event, element in ET.iterparse(stream, events=('end',)):
                if event != 'end' or _tag_name(element) != 'row':
                    continue
                cells = [child for child in element if _tag_name(child) == 'c']
                width = max(
                    (_column_index(cell.attrib.get('r')) for cell in cells),
                    default=-1,
                ) + 1
                row = [''] * width
                for cell in cells:
                    row[_column_index(cell.attrib.get('r'))] = _cell_value(cell, shared)
                element.clear()
                rows.append(row)
            return rows


def _sheet_records(
    path: Path, sheet_name: str, required_headers: tuple[str, ...]
) -> list[dict[str, str]]:
    rows = read_xlsx_sheet(path, sheet_name)
    if not rows:
        raise ValueError(f'Workbook sheet {sheet_name!r} is empty.')
    headers = [clean(header) for header in rows[0]]
    if headers != list(required_headers):
        raise ValueError(
            f'Workbook sheet {sheet_name!r} headers must be {list(required_headers)!r}, '
            f'got {headers!r}.'
        )
    records: list[dict[str, str]] = []
    for line_number, row in enumerate(rows[1:], start=2):
        padded = list(row) + [''] * (len(headers) - len(row))
        records.append({
            header: clean(padded[index]) for index, header in enumerate(headers)
        })
    return records


def _reading_number(raw: str, *, where: str) -> int:
    text = clean(raw)
    if text.isdigit():
        number = int(text)
    else:
        raise ValueError(f'Invalid reading_no at {where}: {raw!r}')
    if not 1 <= number <= EXPECTED_READINGS:
        raise ValueError(f'Reading number out of range at {where}: {raw!r}')
    return number


def _positive_int(raw: str, *, where: str) -> int:
    text = clean(raw)
    if text.isdigit() and int(text) > 0:
        return int(text)
    raise ValueError(f'Invalid positive integer at {where}: {raw!r}')


def parse_evidence_sentences(
    raw: str, *, sentence_count: int, where: str
) -> list[int]:
    """Parse evidence formats like ``2``, ``2,3`` or ``1-6`` (inclusive)."""
    text = clean(raw)
    if not text:
        raise ValueError(f'Blank evidence sentences at {where}.')
    indexes: list[int] = []
    for part in text.split(','):
        part = part.strip()
        if not part:
            raise ValueError(f'Blank evidence entry at {where}.')
        span = EVIDENCE_RANGE.match(part)
        if span is not None:
            start, end = int(span.group(1)), int(span.group(2))
            if start > end:
                raise ValueError(f'Inverted evidence range at {where}: {part!r}')
            indexes.extend(range(start, end + 1))
        elif part.isdigit():
            indexes.append(int(part))
        else:
            raise ValueError(f'Invalid evidence entry at {where}: {part!r}')
    unique = sorted(set(indexes))
    if not unique or any(index < 1 or index > sentence_count for index in unique):
        raise ValueError(f'Evidence sentences out of range at {where}: {raw!r}')
    return unique


def load_reading_workbook(path: Path) -> dict[int, dict[str, Any]]:
    """Load and strictly validate the single canonical reading workbook."""
    reading_rows = _sheet_records(path, 'Readings', (
        'reading_no', 'title_en', 'title_tr', 'level', 'category', 'tags_raw',
    ))
    sentence_rows = _sheet_records(path, 'Sentences', (
        'reading_no', 'sentence_no', 'sentence_en', 'sentence_tr',
    ))
    question_rows = _sheet_records(path, 'Questions', (
        'reading_no', 'question_no', 'question_type', 'question_en',
        'question_tr', 'option_a_en', 'option_a_tr', 'option_b_en',
        'option_b_tr', 'option_c_en', 'option_c_tr', 'option_d_en',
        'option_d_tr', 'correct_option', 'explanation_en', 'explanation_tr',
        'evidence_sentence_no',
    ))
    if len(reading_rows) != EXPECTED_READINGS:
        raise ValueError(
            f'Readings sheet must contain {EXPECTED_READINGS} rows, '
            f'got {len(reading_rows)}.'
        )
    if len(sentence_rows) != EXPECTED_SENTENCES:
        raise ValueError(
            f'Sentences sheet must contain {EXPECTED_SENTENCES} rows, '
            f'got {len(sentence_rows)}.'
        )
    if len(question_rows) != EXPECTED_QUESTIONS:
        raise ValueError(
            f'Questions sheet must contain {EXPECTED_QUESTIONS} rows, '
            f'got {len(question_rows)}.'
        )

    readings: dict[int, dict[str, Any]] = {}
    seen_titles: set[str] = set()
    for line_number, row in enumerate(reading_rows, start=2):
        number = _reading_number(row['reading_no'], where=f'Readings row {line_number}')
        if number in readings:
            raise ValueError(f'Duplicate reading_no: {number:03d}')
        title_en = clean(row['title_en'])
        title_tr = clean(row['title_tr'])
        if not title_en or not title_tr:
            raise ValueError(f'Blank reading title at Readings row {line_number}.')
        title_key = normalized(title_en)
        if title_key in seen_titles:
            raise ValueError(f'Duplicate English reading title: {title_en!r}')
        seen_titles.add(title_key)
        level = canonical_level(row['level'], kind='reading', where=f'reading {number:03d}')
        for field in ('title_en', 'title_tr'):
            if has_invalid_spreadsheet_token(row[field]):
                raise ValueError(f'Spreadsheet token in reading {number:03d}.')
        readings[number] = {
            'sourceNumber': number,
            'title_en': title_en,
            'title_tr': title_tr,
            'level': level,
            'category': clean(row['category']) or None,
            'tags': parse_tag_list(row['tags_raw']),
            'sentences': [],
            'questions': [],
        }
    if set(readings) != set(range(1, EXPECTED_READINGS + 1)):
        raise ValueError('Readings sheet must cover reading numbers 001–800.')

    seen_english_sentences: set[str] = set()
    for line_number, row in enumerate(sentence_rows, start=2):
        number = _reading_number(row['reading_no'], where=f'Sentences row {line_number}')
        sentence_no = _positive_int(row['sentence_no'], where=f'Sentences row {line_number}')
        english = clean(row['sentence_en'])
        turkish = clean(row['sentence_tr'])
        if not english or not turkish:
            raise ValueError(f'Blank EN/TR sentence at Sentences row {line_number}.')
        if has_invalid_spreadsheet_token(english) or has_invalid_spreadsheet_token(turkish):
            raise ValueError(f'Spreadsheet token at Sentences row {line_number}.')
        if english in seen_english_sentences:
            raise ValueError(f'Duplicate English sentence at Sentences row {line_number}.')
        seen_english_sentences.add(english)
        if len(english_tokens(english)) < MIN_SENTENCE_ENGLISH_WORDS:
            raise ValueError(
                f'English sentence below {MIN_SENTENCE_ENGLISH_WORDS} words '
                f'at Sentences row {line_number}.'
            )
        readings[number]['sentences'].append({
            'index': sentence_no,
            'englishText': english,
            'turkishText': turkish,
        })
    for number, reading in readings.items():
        sentences = sorted(reading['sentences'], key=lambda item: item['index'])
        indexes = [item['index'] for item in sentences]
        if [item + 1 for item in range(len(sentences))] != indexes:
            raise ValueError(f'Sentence numbering is not contiguous in reading {number:03d}.')
        if not EXPECTED_READING_SENTENCES_MIN <= len(sentences) <= EXPECTED_READING_SENTENCES_MAX:
            raise ValueError(f'Sentence count out of range in reading {number:03d}.')
        reading['sentences'] = sentences

    correct_distribution: Counter[str] = Counter()
    for line_number, row in enumerate(question_rows, start=2):
        number = _reading_number(row['reading_no'], where=f'Questions row {line_number}')
        question_no = _positive_int(row['question_no'], where=f'Questions row {line_number}')
        if not 1 <= question_no <= EXPECTED_QUESTIONS_PER_READING:
            raise ValueError(f'Question number out of range at Questions row {line_number}.')
        question_type = clean(row['question_type'])
        if question_type not in READING_QUESTION_TYPES:
            raise ValueError(f'Invalid question type at Questions row {line_number}.')
        options_en = [clean(row[f'option_{letter}_en']) for letter in 'abcd']
        options_tr = [clean(row[f'option_{letter}_tr']) for letter in 'abcd']
        if any(not option for option in (*options_en, *options_tr)):
            raise ValueError(f'Blank question option at Questions row {line_number}.')
        if len(set(options_en)) != 4 or len(set(options_tr)) != 4:
            raise ValueError(f'Question options are not unique at Questions row {line_number}.')
        correct = clean(row['correct_option']).upper()
        if correct not in CORRECT_OPTION_INDEX:
            raise ValueError(f'Invalid correct option at Questions row {line_number}.')
        correct_index = CORRECT_OPTION_INDEX[correct]
        correct_distribution[correct] += 1
        question_en = clean(row['question_en'])
        question_tr = clean(row['question_tr'])
        if not question_en or not question_tr:
            raise ValueError(f'Blank question text at Questions row {line_number}.')
        for field in ('question_en', 'question_tr', 'explanation_en', 'explanation_tr',
                      *options_en, *options_tr):
            if has_invalid_spreadsheet_token(field):
                raise ValueError(f'Spreadsheet token at Questions row {line_number}.')
        sentence_count = len(readings[number]['sentences'])
        evidence = parse_evidence_sentences(
            row['evidence_sentence_no'],
            sentence_count=sentence_count,
            where=f'Questions row {line_number}',
        )
        readings[number]['questions'].append({
            'id': f'{number:03d}-{question_no}',
            'sortOrder': question_no,
            'type': question_type,
            'questionCategory': 'comprehension',
            'question': question_en,
            'questionTr': question_tr,
            'options': options_en,
            'optionsTr': options_tr,
            'correctOptionIndex': correct_index,
            'answerEn': options_en[correct_index],
            'answerTr': options_tr[correct_index],
            'explanation': clean(row['explanation_en']) or None,
            'explanationTr': clean(row['explanation_tr']) or None,
            'evidenceSentenceIndexes': evidence,
        })
    for number, reading in readings.items():
        questions = sorted(reading['questions'], key=lambda item: item['sortOrder'])
        if [item['sortOrder'] for item in questions] != [1, 2, 3, 4, 5]:
            raise ValueError(f'Question numbers are not 1–5 in reading {number:03d}.')
        if sorted(item['type'] for item in questions) != sorted(READING_QUESTION_TYPES):
            raise ValueError(f'Question type coverage is invalid in reading {number:03d}.')
        reading['questions'] = questions
    if dict(sorted(correct_distribution.items())) != {letter: 1000 for letter in 'ABCD'}:
        raise ValueError(f'Correct-option distribution is invalid: {dict(correct_distribution)}')
    return readings


def load_legacy_reading_id_map(path: Path) -> dict[str, str]:
    """Load the one-time 001–678 legacy passage-ID migration map."""
    payload = load_json_object(path, 'legacy reading ID map')
    if len(payload) != 678 or set(payload.values()) != {f'{number:03d}' for number in range(1, 679)}:
        raise ValueError('Legacy reading ID map must cover source numbers 001–678.')
    return {str(key): str(value) for key, value in payload.items()}
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
def build(
    source_dir: Path,
    output_dir: Path,
) -> dict[str, Any]:
    """Build public content from the canonical word CSV and reading workbook.

    Reading prose and questions are read only from
    ``PASSAGETR_READINGS_CANONICAL_800_FINAL.xlsx``.  No JSON repair,
    translation, or editorial overlay participates in this path.
    """
    words_source = source_dir / 'canonical' / 'words' / WORDS_CANONICAL_FILENAME
    readings_source = source_dir / 'canonical' / 'readings' / READINGS_CANONICAL_FILENAME
    legacy_map_source = source_dir / READINGS_LEGACY_MAP_RELATIVE_PATH
    dictionary_source = source_dir / 'canonical' / 'dictionary' / 'dictionary_tr_en.xlsx'
    for source in (
        words_source, readings_source, legacy_map_source, dictionary_source,
    ):
        if not source.is_file():
            raise FileNotFoundError(source)

    expected_word_fields = {
        'en_word', 'tr_meaning', 'pos', 'example_en', 'example_tr',
        'synonyms_raw', 'antonyms_raw', 'level', 'tags_raw', 'notes',
    }
    word_rows = read_csv(words_source)
    if len(word_rows) != 9000 or set(word_rows[0]) != expected_word_fields:
        raise ValueError('Word canonical CSV must contain exactly 9,000 expected rows.')
    required_word_fields = (
        'en_word', 'tr_meaning', 'pos', 'example_en', 'example_tr',
        'level', 'tags_raw',
    )
    word_pack_name = 'YDS Canonical 9000'
    words_by_pack: dict[str, list[dict[str, Any]]] = {word_pack_name: []}
    primary_word_ids: dict[str, list[str]] = defaultdict(list)
    seen_headwords: set[str] = set()
    for row_number, row in enumerate(word_rows, start=2):
        if any(not clean(row.get(field)) for field in required_word_fields):
            raise ValueError(f'Word canonical CSV has a blank required field at row {row_number}.')
        english = clean(row['en_word'])
        meaning = clean(row['tr_meaning'])
        examples = (clean(row['example_en']), clean(row['example_tr']))
        if any(has_invalid_spreadsheet_token(value) for value in (english, meaning, *examples)):
            raise ValueError('Word source contains an invalid spreadsheet-error token.')
        normalized_headword = normalized(english)
        if normalized_headword in seen_headwords:
            raise ValueError(f'Duplicate canonical headword: {english!r}')
        seen_headwords.add(normalized_headword)
        tags = parse_tag_list(row['tags_raw'])
        if not tags or any(not is_canonical_word_tag(tag) for tag in tags):
            raise ValueError(f'Invalid canonical word tag at row {row_number}.')
        pos = canonical_pos(row['pos'])
        identifier = word_id(english, pos)
        primary_word_ids[normalize_dictionary_key(english)].append(identifier)
        words_by_pack[word_pack_name].append({
            'id': identifier,
            'packId': pack_id(word_pack_name),
            'enWord': english,
            'trMeaning': meaning,
            'pos': pos,
            'exampleEn': examples[0],
            'exampleTr': examples[1],
            'synonymsRaw': nullable(row.get('synonyms_raw')),
            'antonymsRaw': nullable(row.get('antonyms_raw')),
            'notes': nullable(row.get('notes')),
            'level': canonical_level(row.get('level'), kind='word', where=f'word CSV row {row_number}'),
            'tags': tags,
        })
    if len(seen_headwords) != 9000:
        raise ValueError('Canonical word headword coverage is invalid.')

    workbook = load_reading_workbook(readings_source)
    legacy_number_map = load_legacy_reading_id_map(legacy_map_source)
    numbered_passages: dict[int, dict[str, Any]] = {}
    for source_number, record in workbook.items():
        title = f'{source_number:03d} - {record["title_en"]} ({record["title_tr"]})'
        numbered_passages[source_number] = {
            'id': reading_id(source_number),
            'packId': pack_id(READING_PACK_NAME),
            'title': title,
            'level': record['level'],
            'category': record['category'],
            'tags': record['tags'],
            'author': None,
            'durationMinutes': None,
            'coverAsset': None,
            'coverAltText': None,
            'sentences': record['sentences'],
            'enrichment': {},
            '_displayTitle': record['title_en'],
            '_turkishTitle': record['title_tr'],
            '_questions': record['questions'],
        }

    document_frequency: Counter[str] = Counter()
    for passage in numbered_passages.values():
        document_frequency.update({
            token
            for sentence in passage['sentences']
            for token in english_tokens(sentence['englishText'])
        })

    sentence_count = 0
    question_payload: list[dict[str, Any]] = []
    enrichment_audit = {
        'wordCountReadings': 0,
        'durationReadings': 0,
        'focusWordReadings': 0,
        'summaryReadings': 0,
        'questionReadings': 0,
        'totalQuestions': 0,
        'comprehensionQuestions': 0,
        'productionSentenceOverlays': 0,
    }
    source_missing_numbers: list[int] = []
    for source_number, passage in sorted(numbered_passages.items()):
        sentences = passage['sentences']
        sentence_count += len(sentences)
        if not sentences:
            source_missing_numbers.append(source_number)
        meaningful = [item for item in sentences if clean(item.get('englishText'))]
        summary = ' '.join(item['englishText'] for item in meaningful[:2]) or None
        summary_tr = ' '.join(
            clean(item.get('turkishText')) for item in meaningful[:2] if clean(item.get('turkishText'))
        ) or None
        summary_type = 'extractive'
        questions = passage.pop('_questions')
        content_source = 'canonical_xlsx_readings_800_v1'
        word_count = sum(len(english_tokens(sentence['englishText'])) for sentence in sentences)
        focus_ids = focus_word_ids(
            sentences, primary_word_ids, document_frequency, len(numbered_passages)
        )
        enrichment = {
            'schemaVersion': 1,
            'sourceNumber': f'{source_number:03d}',
            'displayTitle': passage['_displayTitle'],
            'turkishTitle': passage['_turkishTitle'],
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
        if summary_tr is not None:
            enrichment['summaryTr'] = summary_tr
        passage['enrichment'] = enrichment
        passage.pop('_displayTitle')
        passage.pop('_turkishTitle')
        question_payload.append({'sourceNumber': source_number, 'questions': questions})
        enrichment_audit['wordCountReadings'] += int(word_count > 0)
        enrichment_audit['durationReadings'] += int(word_count > 0)
        enrichment_audit['focusWordReadings'] += int(bool(focus_ids))
        enrichment_audit['summaryReadings'] += int(summary is not None)
        enrichment_audit['questionReadings'] += int(bool(questions))
        enrichment_audit['totalQuestions'] += len(questions)
        enrichment_audit['comprehensionQuestions'] += sum(
            question.get('questionCategory') == 'comprehension' for question in questions
        )
    if sentence_count != EXPECTED_SENTENCES:
        raise ValueError(
            f'Canonical reading sentence count must be {EXPECTED_SENTENCES:,}, got {sentence_count}.'
        )
    if enrichment_audit['totalQuestions'] != EXPECTED_QUESTIONS:
        raise ValueError('Reading question coverage is invalid.')

    if output_dir.exists():
        shutil.rmtree(output_dir)
    (output_dir / 'words').mkdir(parents=True)
    (output_dir / 'readings' / 'items').mkdir(parents=True)
    pack_records: list[dict[str, Any]] = []
    word_index: list[dict[str, Any]] = []
    for name, entries in words_by_pack.items():
        identifier = pack_id(name)
        sorted_entries = sorted(entries, key=lambda item: item['enWord'].casefold())
        file_name = f'{identifier}.json'
        write_json(output_dir / 'words' / file_name, {'packId': identifier, 'words': sorted_entries})
        record = {'id': identifier, 'name': name, 'wordCount': len(sorted_entries)}
        pack_records.append(record)
        word_index.append({**record, 'file': f'words/{file_name}'})

    reading_index: list[dict[str, Any]] = []
    for passage in sorted(numbered_passages.values(), key=lambda item: item['title'].casefold()):
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
    legacy_id_map = {
        old_id: reading_id(int(number))
        for old_id, number in legacy_number_map.items()
    }
    write_json(output_dir / 'readings' / 'legacy_id_map.json', {
        'schemaVersion': 1,
        'mapping': legacy_id_map,
    })
    dictionary = build_dictionary(dictionary_source, output_dir)
    question_hash = hashlib.sha256(json_bytes(question_payload)).hexdigest()
    manifest = {
        'schemaVersion': 1,
        'generatedAt': datetime.now(UTC).isoformat(),
        'contentVersion': 'v1',
        'counts': {
            'words': 9000,
            'readings': len(numbered_passages),
            'sentences': sentence_count,
            'dictionaryEntries': dictionary['recordCount'],
            'dictionaryHeadwords': dictionary['uniqueNormalizedHeadwords'],
        },
        'packs': pack_records,
        'wordsIndex': 'words/index.json',
        'readingsIndex': 'readings/index.json',
        'dictionaryIndex': 'dictionary/index.json',
        'legacyReadingIdMap': 'readings/legacy_id_map.json',
        'readingEnrichment': {'schemaVersion': 1, 'wordsPerMinute': READING_WORDS_PER_MINUTE, **enrichment_audit},
        'readingCanonicalSource': {
            'workbook': 'canonical/readings/PASSAGETR_READINGS_CANONICAL_800_FINAL.xlsx',
            'productionSentenceOverlays': 0,
            'sourceMissingReadingNumbers': source_missing_numbers,
        },
        'readingQuestionIntegrity': {
            'schemaVersion': 1,
            'payloadSha256': question_hash,
            'readings': len(numbered_passages),
            'questions': enrichment_audit['totalQuestions'],
        },
        'sourceChecksums': {
            'words': source_hash(words_source),
            'readingsWorkbook': source_hash(readings_source),
            'dictionary': source_hash(dictionary_source),
        },
    }
    write_json(output_dir / 'manifest.json', manifest)
    return {**manifest, 'dictionaryAudit': dictionary['audit']}


def main() -> int:
    parser = argparse.ArgumentParser(description='Build public PASSAGETR static content.')
    parser.add_argument('--source-dir', type=Path, default=ROOT / 'source_data')
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'assets' / 'content' / 'v1')
    args = parser.parse_args()
    manifest = build(
        args.source_dir.resolve(),
        args.output_dir.resolve(),
    )
    print(json.dumps({**manifest['counts'], 'dictionaryAudit': manifest['dictionaryAudit']}, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
