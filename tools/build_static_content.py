#!/usr/bin/env python3
"""Build PASSAGETR public content from its canonical static sources.

Words are read only from the 7,500-record canonical CSV.  Reading EN/TR body
is read only from the canonical passage/sentence CSV pair; no repair,
translation, or editorial JSON overlay participates in production builds.
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
DEFAULT_CURATED_READINGS_RELATIVE_PATH = Path('curated/readings_001_100_curated_v2.json')
WORDS_CANONICAL_FILENAME = 'passagetr_yds_words_canonical_7500_FINAL.csv'
DERIVED_QUESTIONS_FILENAME = 'reading_questions_v1.json'
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
        'word', f'passagetr canonical 7500|{normalized(word)}|{normalized(pos)}'
    )


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
    """Load 001–100 curated metadata and questions, never reading body text."""
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
        questions = record.get('questions')
        if (
            not isinstance(questions, list)
            or len(questions) != 5
        ):
            raise ValueError(f'Invalid curated record {number:03d}')
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


def load_derived_questions(path: Path) -> dict[int, dict[str, Any]]:
    """Load the immutable 101–678 question snapshot without reading body text."""
    payload = load_json_object(path, 'derived reading question snapshot')
    records = payload.get('derivedQuestions')
    if payload.get('schemaVersion') != 1 or not isinstance(records, list):
        raise ValueError('Derived question snapshot has an invalid schema.')
    result: dict[int, dict[str, Any]] = {}
    for record in records:
        if not isinstance(record, dict):
            raise ValueError('Derived question snapshot entry must be an object.')
        source_number = record.get('sourceNumber')
        reading_id = clean(record.get('readingId'))
        questions = record.get('questions')
        if (
            not isinstance(source_number, int)
            or not 101 <= source_number <= 678
            or source_number in result
            or not reading_id
            or not isinstance(questions, list)
        ):
            raise ValueError('Derived question snapshot entry is invalid.')
        result[source_number] = {'readingId': reading_id, 'questions': questions}
    if set(result) != set(range(101, 679)):
        raise ValueError('Derived question snapshot must cover 101–678.')
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


def load_json_object(path: Path, label: str) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding='utf-8'))
    except json.JSONDecodeError as error:
        raise ValueError(f'Invalid {label}: {path}') from error
    if not isinstance(payload, dict):
        raise ValueError(f'{label} must be a JSON object.')
    return payload


def passages_by_source_number(
    passages: dict[str, dict[str, Any]],
) -> dict[int, dict[str, Any]]:
    result: dict[int, dict[str, Any]] = {}
    for passage in passages.values():
        source_text, _, _ = display_titles(passage['title'])
        if source_text is None:
            raise ValueError(f'Passage source number is invalid: {passage["title"]!r}')
        source_number = int(source_text)
        if source_number in result:
            raise ValueError(f'Duplicate passage source number: {source_number}')
        result[source_number] = passage
    if set(result) != set(range(1, 679)):
        raise ValueError('Passage source-number coverage is invalid.')
    return result
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
    curated_package: Path | None = None,
) -> dict[str, Any]:
    """Build public content from the canonical CSV pair and question sources.

    Reading prose is deliberately read only from ``reading_sentences.csv``.
    No JSON repair, translation, or editorial overlay participates in this path.
    """
    words_source = source_dir / 'canonical' / 'words' / WORDS_CANONICAL_FILENAME
    passages_source = source_dir / 'canonical' / 'readings' / 'reading_passages.csv'
    sentences_source = source_dir / 'canonical' / 'readings' / 'reading_sentences.csv'
    questions_source = source_dir / 'canonical' / 'readings' / DERIVED_QUESTIONS_FILENAME
    dictionary_source = source_dir / 'canonical' / 'dictionary' / 'dictionary_tr_en.xlsx'
    curated_package = curated_package or (
        source_dir / DEFAULT_CURATED_READINGS_RELATIVE_PATH
    )
    for source in (
        words_source, passages_source, sentences_source, questions_source,
        dictionary_source, curated_package,
    ):
        if not source.is_file():
            raise FileNotFoundError(source)

    expected_word_fields = {
        'en_word', 'tr_meaning', 'pos', 'example_en', 'example_tr',
        'synonyms_raw', 'antonyms_raw', 'level', 'tags_raw', 'notes',
    }
    word_rows = read_csv(words_source)
    if len(word_rows) != 7500 or set(word_rows[0]) != expected_word_fields:
        raise ValueError('Word canonical CSV must contain exactly 7,500 expected rows.')
    required_word_fields = (
        'en_word', 'tr_meaning', 'pos', 'example_en', 'example_tr',
        'level', 'tags_raw', 'notes',
    )
    word_pack_name = 'YDS Canonical 7500'
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
        if not tags or any(not re.fullmatch(r'[a-z0-9][a-z0-9_-]*', tag) for tag in tags):
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
            'level': nullable(row.get('level')),
            'tags': tags,
        })
    if len(seen_headwords) != 7500:
        raise ValueError('Canonical word headword coverage is invalid.')

    passage_rows = read_csv(passages_source)
    if len(passage_rows) != 678:
        raise ValueError('Reading passage CSV must contain exactly 678 rows.')
    passages: dict[str, dict[str, Any]] = {}
    for row in passage_rows:
        title = clean(row.get('title'))
        source_pack = clean(row.get('pack_name'))
        if not title or not source_pack:
            raise ValueError('Reading passage CSV has a blank required field.')
        key = normalized(title)
        if key in passages:
            raise ValueError(f'Duplicate normalized passage title: {title!r}')
        _, default_display_title, default_turkish_title = display_titles(title)
        passages[key] = {
            'id': passage_id(title),
            'packId': pack_id(source_pack),
            'title': title,
            'level': nullable(row.get('level')),
            'category': nullable(row.get('Category')),
            'tags': parse_tag_list(row.get('tags_raw')),
            'author': None,
            'durationMinutes': None,
            'coverAsset': None,
            'coverAltText': None,
            'sentences': [],
            'enrichment': {},
            '_displayTitle': clean(row.get('display_title_en')) or default_display_title,
            '_turkishTitle': nullable(row.get('display_title_tr')) or default_turkish_title,
        }
    numbered_passages = passages_by_source_number(passages)

    grouped_sentences: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row_number, row in enumerate(read_csv(sentences_source), start=2):
        title = clean(row.get('passage_title'))
        english = clean(row.get('sentence_en'))
        turkish = clean(row.get('sentence_tr'))
        raw_index = clean(row.get('idx'))
        if not all((title, english, turkish, raw_index)):
            raise ValueError(f'Reading sentence CSV has a blank EN/TR field at row {row_number}.')
        try:
            index = int(raw_index)
        except ValueError as error:
            raise ValueError(f'Invalid sentence index for {title!r}: {raw_index!r}') from error
        if index <= 0:
            raise ValueError(f'Invalid positive sentence index for {title!r}.')
        grouped_sentences[normalized(title)].append({
            'index': index, 'englishText': english, 'turkishText': turkish,
        })
    for title_key, sentences in grouped_sentences.items():
        passage = passages.get(title_key)
        if passage is None:
            raise ValueError(f'Sentence has no passage: {title_key!r}')
        indexes = [item['index'] for item in sentences]
        if len(indexes) != len(set(indexes)):
            raise ValueError(f'Duplicate sentence index for {passage["title"]!r}.')
        passage['sentences'] = sorted(sentences, key=lambda item: item['index'])

    curated_readings = load_curated_readings(curated_package)
    derived_questions = load_derived_questions(questions_source)
    for source_number, snapshot in derived_questions.items():
        if snapshot['readingId'] != numbered_passages[source_number]['id']:
            raise ValueError('Derived question snapshot reading ID does not match passage CSV.')

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
        'vocabularyPracticeQuestions': 0,
        'curatedReadings': 0,
        'curatedQuestions': 0,
        'derivedQuestionReadings': 0,
        'productionSentenceOverlays': 0,
    }
    source_missing_numbers: list[int] = []
    for source_number, passage in sorted(numbered_passages.items()):
        sentences = passage['sentences']
        sentence_count += len(sentences)
        if not sentences:
            source_missing_numbers.append(source_number)
        curated = curated_readings.get(source_number)
        if curated is not None:
            summary = curated_text(curated, 'summary_en')
            summary_tr: str | None = curated_text(curated, 'summary_tr')
            summary_type = 'curated'
            questions = curated_questions(curated)
            content_source = 'canonical_csv_curated_questions_v2'
            enrichment_audit['curatedReadings'] += 1
            enrichment_audit['curatedQuestions'] += len(questions)
        else:
            summary = extractive_summary(sentences)
            summary_tr = None
            summary_type = 'extractive'
            questions = copy.deepcopy(derived_questions[source_number]['questions'])
            content_source = 'canonical_csv_question_snapshot_v1'
            enrichment_audit['derivedQuestionReadings'] += 1
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
        enrichment_audit['vocabularyPracticeQuestions'] += sum(
            question.get('questionCategory') == 'vocabulary_practice' for question in questions
        )
    if sentence_count != 6275:
        raise ValueError(f'Canonical reading sentence count must be 6,275, got {sentence_count}.')
    if enrichment_audit['curatedReadings'] != 100 or enrichment_audit['derivedQuestionReadings'] != 578:
        raise ValueError('Reading question source coverage is invalid.')

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
    dictionary = build_dictionary(dictionary_source, output_dir)
    question_hash = hashlib.sha256(json_bytes(question_payload)).hexdigest()
    manifest = {
        'schemaVersion': 1,
        'generatedAt': datetime.now(UTC).isoformat(),
        'contentVersion': 'v1',
        'counts': {
            'words': 7500,
            'readings': len(numbered_passages),
            'sentences': sentence_count,
            'dictionaryEntries': dictionary['recordCount'],
            'dictionaryHeadwords': dictionary['uniqueNormalizedHeadwords'],
        },
        'packs': pack_records,
        'wordsIndex': 'words/index.json',
        'readingsIndex': 'readings/index.json',
        'dictionaryIndex': 'dictionary/index.json',
        'readingEnrichment': {'schemaVersion': 1, 'wordsPerMinute': READING_WORDS_PER_MINUTE, **enrichment_audit},
        'readingCanonicalSource': {
            'passages': 'canonical/readings/reading_passages.csv',
            'sentences': 'canonical/readings/reading_sentences.csv',
            'productionSentenceOverlays': 0,
            'sourceMissingReadingNumbers': source_missing_numbers,
        },
        'readingQuestionIntegrity': {
            'schemaVersion': 1,
            'payloadSha256': question_hash,
            'curatedReadings': 100,
            'derivedReadings': 578,
        },
        'sourceChecksums': {
            'words': source_hash(words_source),
            'passages': source_hash(passages_source),
            'sentences': source_hash(sentences_source),
            'derivedQuestions': source_hash(questions_source),
            'dictionary': source_hash(dictionary_source),
            'curatedReadings': source_hash(curated_package),
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
