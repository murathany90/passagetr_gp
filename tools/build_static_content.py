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
CONTENT_REPAIR_FILENAMES = (
    'reading_content_repairs_v1.json',
    'reading_content_repairs_101_300_v2.json',
)
LEGACY_101_300_TEMPLATE_REPAIRS_RELATIVE_PATH = Path(
    'legacy/reading_content_repairs_101_300_v1_template_history.json'
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
)


def clean(value: str | None) -> str:
    text = (value or '').translate(SMART_QUOTES).replace('\r', ' ').replace('\n', ' ')
    text = re.sub(r'[\u200b\u200c\u200d]', '', text)
    return re.sub(r'\s+', ' ', text).strip()


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
    pre_curated_generated_questions_backup_source = (
        source_dir / 'legacy' / 'pre_curated_generated_questions_backup_v1.json'
    )
    translation_repairs_source = (
        source_dir / QUALITY_DIRECTORY / 'reading_translation_repairs_v1.json'
    )
    content_repair_sources = [
        source_dir / QUALITY_DIRECTORY / filename
        for filename in CONTENT_REPAIR_FILENAMES
    ]
    legacy_template_repairs_source = (
        source_dir / LEGACY_101_300_TEMPLATE_REPAIRS_RELATIVE_PATH
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
        pre_curated_generated_questions_backup_source,
        translation_repairs_source,
        *content_repair_sources,
        legacy_template_repairs_source,
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
    seen_words: set[tuple[str, str]] = set()
    words_by_pack: dict[str, list[dict[str, Any]]] = defaultdict(list)
    primary_word_ids: dict[str, list[str]] = defaultdict(list)
    all_pack_names: set[str] = {'YDS Set 001'}
    for row in word_rows:
        english = clean(row.get('en_word'))
        meaning = clean(row.get('tr_meaning'))
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
    canonical_quality_bands = {
        source_number: reading_quality_band(
            passage['level'],
            len(passage['sentences']),
            sum(len(english_tokens(sentence['englishText'])) for sentence in passage['sentences']),
        )
        for source_number, passage in numbered_passages.items()
    }
    base_content_repairs = load_content_repairs(content_repair_sources[0])
    range_content_repairs = load_content_repairs(content_repair_sources[1])
    legacy_template_repairs = load_content_repairs(legacy_template_repairs_source)
    editorial_audit = editorial_repair_audit(
        legacy_template_repairs, range_content_repairs, numbered_passages
    )
    if editorial_audit['summary']['forbiddenTemplateOccurrencesAfter'] != 0:
        raise ValueError('Production editorial repairs contain forbidden templates.')
    write_json(
        source_dir / REPORTS_DIRECTORY / 'reading_repairs_101_300_editorial_audit_v2.json',
        editorial_audit,
    )
    content_repairs = load_content_repair_overlays(content_repair_sources)
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
        apply_content_repairs(numbered_passages, range_content_repairs)
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
            questions = vocabulary_practice_questions(passage['id'], sentences)
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
    sentence_count = sum(len(passage['sentences']) for passage in passages.values())
    quality_audit = write_quality_reports(
        source_dir,
        numbered_passages,
        translation_repairs,
        content_repair_reasons,
        canonical_quality_bands,
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
        'editorialRepairAudit': editorial_audit['summary'],
        'sourceChecksums': {
            'words': source_hash(words_source), 'passages': source_hash(passages_source),
            'sentences': source_hash(sentences_source), 'dictionary': source_hash(dictionary_source),
            'curatedReadings': source_hash(curated_package),
            'preCuratedGeneratedQuestionsBackup': source_hash(
                pre_curated_generated_questions_backup_source
            ),
            'translationRepairs': source_hash(translation_repairs_source),
            'contentRepairs': source_hash(content_repair_sources[0]),
            'contentRepairs101To300': source_hash(content_repair_sources[1]),
            'legacyEditorialRepairHistory': source_hash(legacy_template_repairs_source),
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
