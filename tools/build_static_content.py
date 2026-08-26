#!/usr/bin/env python3
"""Build PASSAGETR's public, bundled content from the audited CSV sources.

No content is generated or enriched here: fields that do not exist in the
source remain null or empty arrays in the resulting JSON.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import shutil
import uuid
from collections import defaultdict
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
ID_NAMESPACE = uuid.UUID('07cbf023-3cd8-4ae7-a892-097112e35d7f')
SMART_QUOTES = str.maketrans({
    '\u2018': "'", '\u2019': "'", '\u201c': '"', '\u201d': '"',
    '\u00a0': ' ', '\ufeff': '',
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


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open('r', encoding='utf-8-sig', newline='') as handle:
        return list(csv.DictReader(handle, delimiter=';'))


def source_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')


def nullable(value: str | None) -> str | None:
    value = clean(value)
    return value or None


def parse_tag_list(value: str | None) -> list[str]:
    return [item for item in (clean(part) for part in (value or '').split(';')) if item]


def build(source_dir: Path, output_dir: Path) -> dict[str, Any]:
    words_source = source_dir / 'YDS_Set_001.csv'
    passages_source = source_dir / 'readings_passages.csv'
    sentences_source = source_dir / 'readings_sentences.csv'
    pack_map_source = source_dir / 'word_pack_reclassification_report.json'
    for source in (words_source, passages_source, sentences_source):
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
            'id': passage_id(title),
            'packId': pack_id(source_pack),
            'title': title,
            'level': nullable(row.get('level')),
            'category': nullable(row.get('Category')),
            'tags': parse_tag_list(row.get('tags_raw')),
            'summary': None,
            'author': None,
            'durationMinutes': None,
            'coverAsset': None,
            'coverAltText': None,
            'sentences': [],
            'focusWordIds': [],
            'questions': [],
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
            'index': index,
            'englishText': english,
            'turkishText': nullable(row.get('sentence_tr')),
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
    manifest = {
        'schemaVersion': 1,
        'generatedAt': datetime.now(UTC).isoformat(),
        'contentVersion': 'v1',
        'counts': {'words': sum(len(items) for items in words_by_pack.values()), 'readings': len(passages), 'sentences': sentence_count},
        'packs': pack_records,
        'wordsIndex': 'words/index.json',
        'readingsIndex': 'readings/index.json',
        'sourceChecksums': {
            'words': source_hash(words_source),
            'passages': source_hash(passages_source),
            'sentences': source_hash(sentences_source),
            **({'wordPackMap': source_hash(pack_map_source)} if pack_map_source.is_file() else {}),
        },
    }
    write_json(output_dir / 'manifest.json', manifest)
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description='Build public PASSAGETR static content.')
    parser.add_argument('--source-dir', type=Path, default=ROOT / 'source_data')
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'assets' / 'content' / 'v1')
    args = parser.parse_args()
    manifest = build(args.source_dir.resolve(), args.output_dir.resolve())
    print(json.dumps(manifest['counts'], ensure_ascii=False))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
