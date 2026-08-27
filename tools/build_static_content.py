#!/usr/bin/env python3
"""Build PASSAGETR's public, bundled content from audited local sources.

The builder only normalizes and partitions source data. It never translates,
summarizes, or otherwise invents content. The Excel dictionary is a build-time
input; the Flutter application reads only the JSON assets produced here.
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


def build(source_dir: Path, output_dir: Path) -> dict[str, Any]:
    words_source = source_dir / 'YDS_Set_001.csv'
    passages_source = source_dir / 'readings_passages.csv'
    sentences_source = source_dir / 'readings_sentences.csv'
    dictionary_source = source_dir / 'dictionary.xlsx'
    pack_map_source = source_dir / 'word_pack_reclassification_report.json'
    for source in (words_source, passages_source, sentences_source, dictionary_source):
        if not source.is_file():
            raise FileNotFoundError(source)

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
            'tags': parse_tag_list(row.get('tags_raw')), 'summary': None, 'author': None,
            'durationMinutes': None, 'coverAsset': None, 'coverAltText': None,
            'sentences': [], 'focusWordIds': [], 'questions': [],
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
        reading_index.append({
            key: passage[key] for key in (
                'id', 'packId', 'title', 'level', 'category', 'tags', 'summary',
                'author', 'durationMinutes', 'coverAsset', 'coverAltText',
            )
        } | {'sentenceCount': len(passage['sentences']), 'file': f'readings/items/{file_name}'})

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
        'sourceChecksums': {
            'words': source_hash(words_source), 'passages': source_hash(passages_source),
            'sentences': source_hash(sentences_source), 'dictionary': source_hash(dictionary_source),
            **({'wordPackMap': source_hash(pack_map_source)} if pack_map_source.is_file() else {}),
        },
    }
    write_json(output_dir / 'manifest.json', manifest)
    return {**manifest, 'dictionaryAudit': dictionary['audit']}


def main() -> int:
    parser = argparse.ArgumentParser(description='Build public PASSAGETR static content.')
    parser.add_argument('--source-dir', type=Path, default=ROOT / 'source_data')
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'assets' / 'content' / 'v1')
    args = parser.parse_args()
    manifest = build(args.source_dir.resolve(), args.output_dir.resolve())
    print(json.dumps({**manifest['counts'], 'dictionaryAudit': manifest['dictionaryAudit']}, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
