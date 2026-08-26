#!/usr/bin/env python3
"""Validate the normalized public content bundle before a Pages deployment."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXPECTED = {'words': 5314, 'readings': 678, 'sentences': 5242}


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding='utf-8'))


def validate(content_dir: Path) -> dict[str, int]:
    manifest = load(content_dir / 'manifest.json')
    counts = manifest.get('counts', {})
    if counts != EXPECTED:
        raise ValueError(f'Manifest count mismatch: expected {EXPECTED}, got {counts}')

    words_index = load(content_dir / manifest['wordsIndex'])
    words = []
    for pack in words_index.get('packs', []):
        payload = load(content_dir / pack['file'])
        entries = payload.get('words', [])
        if payload.get('packId') != pack.get('id') or len(entries) != pack.get('wordCount'):
            raise ValueError(f'Invalid word pack: {pack.get("name")}')
        words.extend(entries)
    if len(words) != EXPECTED['words'] or len({item['id'] for item in words}) != len(words):
        raise ValueError('Word count or unique word IDs are invalid')
    if any(not item.get('enWord') or not item.get('trMeaning') or not item.get('pos') for item in words):
        raise ValueError('A word lacks required content')

    readings_index = load(content_dir / manifest['readingsIndex'])
    readings = readings_index.get('readings', [])
    if len(readings) != EXPECTED['readings'] or len({item['id'] for item in readings}) != len(readings):
        raise ValueError('Reading count or unique reading IDs are invalid')
    sentence_count = 0
    for item in readings:
        payload = load(content_dir / item['file'])
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
    return {'words': len(words), 'readings': len(readings), 'sentences': sentence_count}


def main() -> int:
    parser = argparse.ArgumentParser(description='Validate public PASSAGETR static content.')
    parser.add_argument('--content-dir', type=Path, default=ROOT / 'assets' / 'content' / 'v1')
    args = parser.parse_args()
    counts = validate(args.content_dir.resolve())
    print(json.dumps(counts, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
