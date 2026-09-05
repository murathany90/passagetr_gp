#!/usr/bin/env python3
"""Validate the generated PASSAGETR public study-module contract."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import build_study_content as study  # noqa: E402


SOURCE = ROOT / study.SOURCE_RELATIVE_PATH
OUTPUT = ROOT / 'assets' / 'content' / 'study'


def load_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(payload, dict):
        raise ValueError(f'JSON object expected: {path}')
    return payload


def main() -> int:
    workbook = study.load_workbook(SOURCE)
    expected_manifest, expected_payloads = study.build_payloads(workbook, SOURCE)
    manifest_path = OUTPUT / 'study_manifest.json'
    if not manifest_path.is_file():
        raise ValueError('Missing generated study manifest.')
    manifest = load_json(manifest_path)
    if manifest != expected_manifest:
        raise ValueError('Study manifest does not match canonical workbook.')
    generated_ids = {module['module_id'] for module in manifest.get('modules', [])}
    expected_ids = {f'study-{number:04d}' for number in range(1, 13)}
    if generated_ids != set(expected_payloads) or generated_ids != expected_ids:
        raise ValueError('Generated study module IDs are incomplete.')
    for module_id, expected in expected_payloads.items():
        actual = load_json(OUTPUT / 'modules' / study.module_filename(module_id))
        if actual != expected:
            raise ValueError(f'Generated study module drift: {module_id}')
    print(json.dumps({
        'canonicalExcelParse': 'PASS',
        'studyValidator': 'PASS',
        'modules': len(expected_payloads),
        'moduleIds': sorted(generated_ids),
        'moduleChecks': expected_manifest['validation']['moduleChecks'],
    }, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(f'STUDY_VALIDATION_ERROR: {error}', file=sys.stderr)
        raise SystemExit(1)
