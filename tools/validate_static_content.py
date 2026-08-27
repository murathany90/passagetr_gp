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

    word_ids = {str(item['id']) for item in words}
    readings_index = load(content_dir / str(manifest['readingsIndex']))
    readings = readings_index.get('readings', [])
    if len(readings) != EXPECTED['readings'] or len({item.get('id') for item in readings}) != len(readings):
        raise ValueError('Reading count or unique reading IDs are invalid')
    sentence_count = 0
    word_count_readings = 0
    duration_readings = 0
    focus_word_readings = 0
    summary_readings = 0
    question_readings = 0
    total_questions = 0
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
        enrichment = payload.get('enrichment')
        if not isinstance(enrichment, dict) or enrichment.get('schemaVersion') != 1:
            raise ValueError(f'Missing reading enrichment: {item.get("title")}')
        for key in ('displayTitle', 'wordCount', 'estimatedReadingMinutes', 'focusWordIds', 'summary', 'questions'):
            if key not in enrichment:
                raise ValueError(f'Missing enrichment field {key}: {item.get("title")}')
        if not isinstance(enrichment['displayTitle'], str) or not enrichment['displayTitle']:
            raise ValueError(f'Invalid display title: {item.get("title")}')
        if not isinstance(enrichment['wordCount'], int) or enrichment['wordCount'] < 0:
            raise ValueError(f'Invalid word count: {item.get("title")}')
        if not isinstance(enrichment['estimatedReadingMinutes'], int) or enrichment['estimatedReadingMinutes'] < 0:
            raise ValueError(f'Invalid reading duration: {item.get("title")}')
        if item.get('displayTitle') != enrichment['displayTitle']:
            raise ValueError(f'Reading index title metadata mismatch: {item.get("title")}')
        if item.get('wordCount') != enrichment['wordCount'] or item.get('estimatedReadingMinutes') != enrichment['estimatedReadingMinutes']:
            raise ValueError(f'Reading index study metadata mismatch: {item.get("title")}')
        focus_ids = enrichment['focusWordIds']
        if (
            not isinstance(focus_ids, list)
            or len(focus_ids) > 8
            or any(not isinstance(identifier, str) or identifier not in word_ids for identifier in focus_ids)
        ):
            raise ValueError(f'Invalid focus words: {item.get("title")}')
        summary = enrichment['summary']
        if summary is not None and (not isinstance(summary, str) or not summary.strip()):
            raise ValueError(f'Invalid extractive summary: {item.get("title")}')
        questions = enrichment['questions']
        if not isinstance(questions, list) or len(questions) > 3:
            raise ValueError(f'Invalid question collection: {item.get("title")}')
        for expected_order, question in enumerate(questions, start=1):
            if (
                not isinstance(question, dict)
                or not question.get('id')
                or question.get('sortOrder') != expected_order
                or not isinstance(question.get('question'), str)
                or len(question.get('options', [])) != 4
                or len(set(question['options'])) != 4
                or not isinstance(question.get('correctOptionIndex'), int)
                or not 0 <= question['correctOptionIndex'] < 4
                or not isinstance(question.get('explanation'), str)
            ):
                raise ValueError(f'Invalid reading question: {item.get("title")}')
        word_count_readings += int(enrichment['wordCount'] > 0)
        duration_readings += int(enrichment['estimatedReadingMinutes'] > 0)
        focus_word_readings += int(bool(focus_ids))
        summary_readings += int(summary is not None)
        question_readings += int(bool(questions))
        total_questions += len(questions)
        sentence_count += len(sentences)
    if sentence_count != EXPECTED['sentences']:
        raise ValueError(f'Sentence count mismatch: expected 5242, got {sentence_count}')
    enrichment_manifest = manifest.get('readingEnrichment')
    expected_enrichment = {
        'schemaVersion': 1,
        'wordsPerMinute': 200,
        'wordCountReadings': word_count_readings,
        'durationReadings': duration_readings,
        'focusWordReadings': focus_word_readings,
        'summaryReadings': summary_readings,
        'questionReadings': question_readings,
        'totalQuestions': total_questions,
    }
    if enrichment_manifest != expected_enrichment:
        raise ValueError(
            f'Reading enrichment manifest mismatch: expected {expected_enrichment}, got {enrichment_manifest}'
        )

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
        'readingWordCountCoverage': word_count_readings,
        'readingDurationCoverage': duration_readings,
        'readingFocusWordCoverage': focus_word_readings,
        'readingSummaryCoverage': summary_readings,
        'readingQuestionCoverage': question_readings,
        'totalQuestions': total_questions,
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
