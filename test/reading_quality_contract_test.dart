import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canonical word CSV is the sole 9,000-record production source',
      () async {
    const script = r'''
import sys
from pathlib import Path
sys.path.insert(0, 'tools')
import build_static_content as builder

new_source = Path('source_data/canonical/words/passagetr_yds_words_canonical_9000_FINAL_v2.csv')
assert new_source.is_file()
assert list(new_source.parent.glob('*.csv')) == [new_source]
rows = builder.read_csv(new_source)
assert len(rows) == 9000
assert len({builder.normalized(row['en_word']) for row in rows}) == 9000
tags = {tag for row in rows for tag in builder.parse_tag_list(row['tags_raw'])}
assert len(tags) == 66
assert all(builder.is_canonical_word_tag(tag) and '_' not in tag for tag in tags)
assert 'technology & it' in tags
assert all(not builder.has_invalid_spreadsheet_token(value) for row in rows for value in row.values())
levels = {builder.canonical_level(row['level'], kind='word', where='contract') for row in rows}
assert levels <= set(builder.CANONICAL_LEVELS), levels
''';
    final result = await Process.run(
      'python',
      <String>['-c', script],
      workingDirectory: Directory.current.path,
    );

    expect(result.exitCode, 0, reason: result.stderr.toString());
  });

  test('reading workbook is the sole 800-reading canonical source', () async {
    const script = r'''
import json
import sys
sys.path.insert(0, 'tools')
import build_static_content as builder
from pathlib import Path

workbook = Path('source_data/canonical/readings/PASSAGETR_READINGS_CANONICAL_800_FINAL.xlsx')
assert workbook.is_file()
assert sorted(path.name for path in workbook.parent.iterdir() if path.is_file()) == [workbook.name]
records = builder.load_reading_workbook(workbook)
assert len(records) == 800
assert set(records) == set(range(1, 801))
assert sum(len(item['sentences']) for item in records.values()) == 7500
assert sum(len(item['questions']) for item in records.values()) == 4000
english = [sentence['englishText'] for item in records.values() for sentence in item['sentences']]
assert len(set(english)) == 7500
levels = {item['level'] for item in records.values()}
assert levels <= set(builder.CANONICAL_LEVELS), levels
for number, item in records.items():
    assert len(item['sentences']) in range(6, 13)
    assert [question['sortOrder'] for question in item['questions']] == [1, 2, 3, 4, 5]
    assert sorted(question['type'] for question in item['questions']) == sorted(builder.READING_QUESTION_TYPES)
allowed = {
    (workbook.parent.parent / 'words' / 'passagetr_yds_words_canonical_9000_FINAL_v2.csv').resolve(),
    workbook.resolve(),
    Path('source_data/mappings/reading_legacy_ids_001_678.json').resolve(),
    Path('source_data/canonical/dictionary/dictionary_tr_en.xlsx').resolve(),
    Path('source_data/canonical/study/PASSAGETR_YDS_Study_Canonical_v2_Module_01-30.xlsx').resolve(),
    Path('source_data/canonical/tests/passagetr_test_bank.xlsx').resolve(),
}
assert {path.resolve() for path in Path('source_data').rglob('*') if path.is_file()} == allowed
manifest = json.load(open('assets/content/v1/manifest.json', encoding='utf-8'))
assert manifest['counts']['readings'] == 800
assert manifest['counts']['sentences'] == 7500
assert manifest['readingCanonicalSource']['workbook'] == 'canonical/readings/PASSAGETR_READINGS_CANONICAL_800_FINAL.xlsx'
assert manifest['readingQuestionIntegrity']['readings'] == 800
assert manifest['readingQuestionIntegrity']['questions'] == 4000
assert manifest['readingEnrichment']['focusWordReadings'] == 800
''';
    final result = await Process.run(
      'python',
      <String>['-c', script],
      workingDirectory: Directory.current.path,
    );

    expect(result.exitCode, 0, reason: result.stderr.toString());
  });

  test('generated reading body, questions and titles match the workbook',
      () async {
    const script = r'''
import json
import re
import sys
sys.path.insert(0, 'tools')
import build_static_content as builder
from pathlib import Path

records = builder.load_reading_workbook(
    Path('source_data/canonical/readings/PASSAGETR_READINGS_CANONICAL_800_FINAL.xlsx'))
index = json.load(open('assets/content/v1/readings/index.json', encoding='utf-8'))['readings']
assert len(index) == 800
title_pattern = re.compile(r'^\d{3} - .+ \(.+\)$')
for entry in index:
    number = int(entry['sourceNumber'])
    expected = records[number]
    item = json.load(open('assets/content/v1/' + entry['file'], encoding='utf-8'))
    assert item['id'] == builder.reading_id(number)
    expected_title = '%03d - %s (%s)' % (number, expected['title_en'], expected['title_tr'])
    assert item['title'] == expected_title, number
    assert entry['title'] == expected_title, number
    assert title_pattern.match(entry['title']), entry['title']
    assert item['sentences'] == expected['sentences']
    assert item['enrichment']['questions'] == expected['questions']
    assert item['enrichment']['summaryType'] == 'extractive'
    assert len(item['enrichment']['focusWordIds']) > 0
''';
    final result = await Process.run(
      'python',
      <String>['-c', script],
      workingDirectory: Directory.current.path,
    );

    expect(result.exitCode, 0, reason: result.stderr.toString());
  });
}
