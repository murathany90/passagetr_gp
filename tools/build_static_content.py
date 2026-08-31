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


def focus_word_ids(
    sentences: list[dict[str, Any]],
    primary_word_ids: dict[str, list[str]],
) -> list[str]:
    """Select up to eight in-passage educational words from the 5,314-word set."""
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
    for token, _ in sorted(
        frequency.items(), key=lambda item: (-item[1], first_position[item[0]], item[0])
    ):
        for identifier in primary_word_ids[token]:
            if identifier not in seen_ids:
                seen_ids.add(identifier)
                selected.append(identifier)
                break
        if len(selected) == 8:
            break
    return selected


def comprehension_questions(
    passage_identifier: str,
    sentences: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    """Make deterministic cloze/detail checks from exact source sentences only.

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
            'question': (
                f'Metindeki {sentence["index"]}. cümleyi doğru kelimeyle tamamlayın:\n{excerpt}'
            ),
            'options': options,
            'correctOptionIndex': options.index(target),
            'explanation': (
                f'Cevap, metnin {sentence["index"]}. cümlesindeki “{target}” sözcüğüdür.'
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
    untouched_baseline_source = (
        source_dir / 'baselines' / 'readings_101_678_baseline_v1.json'
    )
    curated_package = curated_package or (
        source_dir / DEFAULT_CURATED_READINGS_RELATIVE_PATH
    )
    for source in (
        words_source,
        passages_source,
        sentences_source,
        dictionary_source,
        pre_curated_generated_questions_backup_source,
        untouched_baseline_source,
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

    enrichment_audit = {
        'wordCountReadings': 0,
        'durationReadings': 0,
        'focusWordReadings': 0,
        'summaryReadings': 0,
        'questionReadings': 0,
        'totalQuestions': 0,
        'curatedReadings': 0,
        'curatedSentences': 0,
        'curatedQuestions': 0,
    }
    for passage in passages.values():
        source_number, display_title, turkish_title = display_titles(passage['title'])
        curated = curated_readings.get(int(source_number)) if source_number else None
        if curated is not None:
            sentences = [
                {
                    'index': sentence['index'],
                    'englishText': curated_text(sentence, 'en'),
                    'turkishText': curated_text(sentence, 'tr'),
                }
                for sentence in curated['sentences']
            ]
            passage['sentences'] = sentences
            display_title = curated_text(curated, 'replacement_title_en')
            turkish_title = curated_text(curated, 'replacement_title_tr')
            summary = curated_text(curated, 'summary_en')
            summary_tr: str | None = curated_text(curated, 'summary_tr')
            questions = curated_questions(curated)
            content_source = 'curated_v2'
            enrichment_audit['curatedReadings'] += 1
            enrichment_audit['curatedSentences'] += len(sentences)
            enrichment_audit['curatedQuestions'] += len(questions)
        else:
            sentences = passage['sentences']
            summary = extractive_summary(sentences)
            summary_tr = None
            questions = comprehension_questions(passage['id'], sentences)
            content_source = 'derived_v1'
        word_count = sum(
            len(english_tokens(sentence['englishText'])) for sentence in sentences
        )
        focus_ids = focus_word_ids(sentences, primary_word_ids)
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
            'questions': questions,
        }
        if content_source == 'curated_v2':
            enrichment['contentSource'] = content_source
            enrichment['summaryTr'] = summary_tr
        passage['enrichment'] = enrichment
        enrichment_audit['wordCountReadings'] += int(word_count > 0)
        enrichment_audit['durationReadings'] += int(word_count > 0)
        enrichment_audit['focusWordReadings'] += int(bool(focus_ids))
        enrichment_audit['summaryReadings'] += int(summary is not None)
        enrichment_audit['questionReadings'] += int(bool(questions))
        enrichment_audit['totalQuestions'] += len(questions)

    if enrichment_audit['curatedReadings'] != len(curated_readings):
        raise ValueError('Every curated reading must map to exactly one source_number.')
    sentence_count = sum(len(passage['sentences']) for passage in passages.values())

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
        'sourceChecksums': {
            'words': source_hash(words_source), 'passages': source_hash(passages_source),
            'sentences': source_hash(sentences_source), 'dictionary': source_hash(dictionary_source),
            'curatedReadings': source_hash(curated_package),
            'preCuratedGeneratedQuestionsBackup': source_hash(
                pre_curated_generated_questions_backup_source
            ),
            'curatedUntouchedBaseline': source_hash(untouched_baseline_source),
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
