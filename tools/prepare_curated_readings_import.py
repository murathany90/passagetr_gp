#!/usr/bin/env python3
"""Prepare immutable audit inputs before importing curated readings 001–100.

This tool exports the currently bundled questions and byte-level fingerprints
for readings 101–678. It must run while the pre-curation bundle is still
present; the main static-content builder never overwrites these audit files.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CURATED = (
    ROOT
    / 'docs'
    / 'passagetr_readings_001_100_curated_v2'
    / 'passagetr_readings_001_100_curated_v2'
    / 'passagetr_readings_001_100_curated_v2.json'
)


def load(path: Path) -> dict[str, Any] | list[Any]:
    value = json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(value, (dict, list)):
        raise ValueError(f'JSON object or list expected: {path}')
    return value


def source_number(value: object) -> int:
    try:
        result = int(str(value))
    except (TypeError, ValueError) as error:
        raise ValueError(f'Invalid source number: {value!r}') from error
    if not 1 <= result <= 678:
        raise ValueError(f'Out-of-range source number: {result}')
    return result


def curated_records(path: Path) -> dict[int, dict[str, Any]]:
    raw = load(path)
    records = raw.get('readings', raw) if isinstance(raw, dict) else raw
    if not isinstance(records, list) or len(records) != 100:
        raise ValueError('Curated package must contain exactly 100 readings.')
    result: dict[int, dict[str, Any]] = {}
    for record in records:
        if not isinstance(record, dict):
            raise ValueError('Curated record must be an object.')
        number = source_number(record.get('source_number'))
        if number > 100 or number in result:
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
            raise ValueError(f'Invalid curated item {number:03d}')
        result[number] = record
    if set(result) != set(range(1, 101)):
        raise ValueError('Curated package must cover source numbers 001–100.')
    return result


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, separators=(',', ':')),
        encoding='utf-8',
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description='Export legacy reading questions before curated import.'
    )
    parser.add_argument('--curated-package', type=Path, default=DEFAULT_CURATED)
    parser.add_argument(
        '--content-dir', type=Path, default=ROOT / 'assets' / 'content' / 'v1'
    )
    parser.add_argument(
        '--legacy-output',
        type=Path,
        default=ROOT / 'source_data' / 'legacy_reading_questions_v1.json',
    )
    parser.add_argument(
        '--baseline-output',
        type=Path,
        default=ROOT
        / 'source_data'
        / 'curated_readings_001_100_untouched_baseline_v1.json',
    )
    args = parser.parse_args()
    curated = curated_records(args.curated_package.resolve())
    if args.legacy_output.exists() or args.baseline_output.exists():
        raise FileExistsError('Audit outputs already exist; refusing to overwrite them.')

    content_dir = args.content_dir.resolve()
    index = load(content_dir / 'readings' / 'index.json')
    if not isinstance(index, dict) or not isinstance(index.get('readings'), list):
        raise ValueError('Reading index is invalid.')
    by_number: dict[int, dict[str, Any]] = {}
    for item in index['readings']:
        if not isinstance(item, dict):
            raise ValueError('Reading index item is invalid.')
        number = source_number(item.get('sourceNumber'))
        if number in by_number:
            raise ValueError(f'Duplicate source number in reading index: {number}')
        by_number[number] = item
    if set(by_number) != set(range(1, 679)):
        raise ValueError('Reading index must cover source numbers 001–678.')

    legacy_readings: list[dict[str, Any]] = []
    untouched_readings: list[dict[str, Any]] = []
    source_title_mismatches: list[int] = []
    for number in range(1, 679):
        index_item = by_number[number]
        file_path = content_dir / str(index_item['file'])
        raw = file_path.read_bytes()
        item = json.loads(raw)
        if number <= 100:
            if item.get('title') != curated[number].get('source_title'):
                source_title_mismatches.append(number)
            enrichment = item.get('enrichment', {})
            questions = enrichment.get('questions', [])
            if not isinstance(questions, list):
                raise ValueError(f'Legacy questions are invalid for {number:03d}')
            legacy_readings.append({
                'readingId': index_item['id'],
                'sourceNumber': number,
                'sourceTitle': item['title'],
                'questions': questions,
            })
        else:
            untouched_readings.append({
                'readingId': index_item['id'],
                'sourceNumber': number,
                'file': index_item['file'],
                'sha256': hashlib.sha256(raw).hexdigest(),
            })

    legacy_payload = {
        'schemaVersion': 1,
        'source': 'pre-curated assets/content/v1/readings/items',
        'curatedPackageVersion': 'passagetr_readings_001_100_curated_v2',
        'readings': legacy_readings,
        'questionCount': sum(len(item['questions']) for item in legacy_readings),
        'sourceTitleMismatches': source_title_mismatches,
    }
    baseline_payload = {
        'schemaVersion': 1,
        'source': 'pre-curated assets/content/v1/readings/items',
        'curatedPackageVersion': 'passagetr_readings_001_100_curated_v2',
        'readings': untouched_readings,
    }
    write_json(args.legacy_output.resolve(), legacy_payload)
    write_json(args.baseline_output.resolve(), baseline_payload)
    print(
        json.dumps(
            {
                'legacyReadings': len(legacy_readings),
                'legacyQuestions': legacy_payload['questionCount'],
                'untouchedReadings': len(untouched_readings),
                'sourceTitleMismatches': len(source_title_mismatches),
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
