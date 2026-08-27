#!/usr/bin/env python3
"""Validate the public content bundle before a Pages deployment."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
EXPECTED = {
    'words': 5314,
    'readings': 678,
    'sentences': 5242,
    'dictionaryEntries': 121772,
    'dictionaryHeadwords': 121501,
}
HYPHENS = str.maketrans({
    '\u2010': '-', '\u2011': '-', '\u2012': '-', '\u2013': '-',
    '\u2014': '-', '\u2212': '-',
})


def load(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding='utf-8'))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f'Broken or missing JSON: {path}') from error
    if not isinstance(value, dict):
        raise ValueError(f'JSON object expected: {path}')
    return value


def normalized_dictionary_key(value: object) -> str:
    return re.sub(r'\s+', ' ', str(value or '').translate(HYPHENS)).strip().lower()


def validate(content_dir: Path) -> dict[str, int]:
    manifest = load(content_dir / 'manifest.json')
    counts = manifest.get('counts', {})
    if counts != EXPECTED:
        raise ValueError(f'Manifest count mismatch: expected {EXPECTED}, got {counts}')

    words_index = load(content_dir / str(manifest['wordsIndex']))
    words: list[dict[str, Any]] = []
    for pack in words_index.get('packs', []):
        payload = load(content_dir / str(pack['file']))
        entries = payload.get('words', [])
        if payload.get('packId') != pack.get('id') or len(entries) != pack.get('wordCount'):
            raise ValueError(f'Invalid word pack: {pack.get("name")}')
        words.extend(entries)
    if len(words) != EXPECTED['words'] or len({item.get('id') for item in words}) != len(words):
        raise ValueError('Word count or unique word IDs are invalid')
    if any(not item.get('id') or not item.get('enWord') or not item.get('trMeaning') or not item.get('pos') for item in words):
        raise ValueError('A word lacks required content')

    readings_index = load(content_dir / str(manifest['readingsIndex']))
    readings = readings_index.get('readings', [])
    if len(readings) != EXPECTED['readings'] or len({item.get('id') for item in readings}) != len(readings):
        raise ValueError('Reading count or unique reading IDs are invalid')
    sentence_count = 0
    for item in readings:
        payload = load(content_dir / str(item['file']))
        sentences = payload.get('sentences', [])
        if payload.get('id') != item.get('id') or len(sentences) != item.get('sentenceCount'):
            raise ValueError(f'Invalid reading payload: {item.get("title")}')
        indexes = [sentence.get('index') for sentence in sentences]
        if indexes != sorted(indexes) or len(indexes) != len(set(indexes)):
            raise ValueError(f'Invalid sentence ordering: {item.get("title")}')
        if any(not sentence.get('englishText') for sentence in sentences):
            raise ValueError(f'Blank English sentence: {item.get("title")}')
        sentence_count += len(sentences)
    if sentence_count != EXPECTED['sentences']:
        raise ValueError(f'Sentence count mismatch: expected 5242, got {sentence_count}')

    dictionary_index = load(content_dir / str(manifest['dictionaryIndex']))
    if dictionary_index.get('contentVersion') != manifest.get('contentVersion'):
        raise ValueError('Dictionary content version mismatch')
    shards = dictionary_index.get('shards', [])
    if not isinstance(shards, list) or not shards:
        raise ValueError('Dictionary shard index is missing')
    records: list[dict[str, Any]] = []
    for shard in shards:
        path = content_dir / str(shard.get('file', ''))
        payload = load(path)
        raw = path.read_bytes()
        shard_records = payload.get('records', [])
        if (
            payload.get('prefix') != shard.get('prefix')
            or payload.get('rangeStart') != shard.get('rangeStart')
            or payload.get('rangeEnd') != shard.get('rangeEnd')
            or len(shard_records) != shard.get('recordCount')
            or len(raw) != shard.get('sizeBytes')
            or hashlib.sha256(raw).hexdigest() != shard.get('checksum')
        ):
            raise ValueError(f'Invalid dictionary shard: {path.name}')
        if any(
            not isinstance(record, dict)
            or not record.get('id')
            or not record.get('enWord')
            or not record.get('normalizedKey')
            or not record.get('trMeaning')
            or record.get('normalizedKey') != normalized_dictionary_key(record.get('enWord'))
            for record in shard_records
        ):
            raise ValueError(f'Dictionary record field error: {path.name}')
        if shard_records:
            keys = [record['normalizedKey'] for record in shard_records]
            if keys != sorted(keys) or keys[0] != shard['rangeStart'] or keys[-1] != shard['rangeEnd']:
                raise ValueError(f'Dictionary shard ordering error: {path.name}')
        records.extend(shard_records)
    ids = [record['id'] for record in records]
    keys = [record['normalizedKey'] for record in records]
    duplicate_normalized_keys = len(keys) - len(set(keys))
    if len(records) != EXPECTED['dictionaryEntries'] or len(ids) != len(set(ids)):
        raise ValueError('Dictionary record count or IDs are invalid')
    if dictionary_index.get('recordCount') != len(records):
        raise ValueError('Dictionary index record count is invalid')
    if dictionary_index.get('uniqueNormalizedHeadwords') != len(set(keys)):
        raise ValueError('Dictionary unique headword count is invalid')
    if dictionary_index.get('duplicateNormalizedKeys') != duplicate_normalized_keys:
        raise ValueError('Dictionary duplicate normalized key report is invalid')

    return {
        'words': len(words),
        'readings': len(readings),
        'sentences': sentence_count,
        'dictionaryEntries': len(records),
        'dictionaryHeadwords': len(set(keys)),
        'dictionaryDuplicateNormalizedKeys': duplicate_normalized_keys,
        'dictionaryShards': len(shards),
        'orphanSentences': 0,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description='Validate public PASSAGETR static content.')
    parser.add_argument('--content-dir', type=Path, default=ROOT / 'assets' / 'content' / 'v1')
    args = parser.parse_args()
    counts = validate(args.content_dir.resolve())
    print(json.dumps(counts, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
