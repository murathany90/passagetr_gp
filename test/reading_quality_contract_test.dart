import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canonical word CSV is the sole 7,500-record production source',
      () async {
    const script = r'''
import sys
from pathlib import Path
sys.path.insert(0, 'tools')
import build_static_content as builder

new_source = Path('source_data/canonical/words/passagetr_yds_words_canonical_7500_FINAL.csv')
old_source = Path('source_data/canonical/words') / ('yds_words' + '_set_001.csv')
assert new_source.is_file()
assert not old_source.exists()
rows = builder.read_csv(new_source)
assert len(rows) == 7500
assert len({builder.normalized(row['en_word']) for row in rows}) == 7500
assert len({tag for row in rows for tag in builder.parse_tag_list(row['tags_raw'])}) == 66
assert all(not builder.has_invalid_spreadsheet_token(value) for row in rows for value in row.values())
''';
    final result = await Process.run(
      'python',
      <String>['-c', script],
      workingDirectory: Directory.current.path,
    );

    expect(result.exitCode, 0, reason: result.stderr.toString());
  });

  test('generated reading body is exactly the canonical EN/TR CSV', () async {
    const script = r'''
import json
import sys
from collections import defaultdict
from pathlib import Path
sys.path.insert(0, 'tools')
import build_static_content as builder

source = Path('source_data/canonical/readings')
passages = builder.read_csv(source / 'reading_passages.csv')
sentences = builder.read_csv(source / 'reading_sentences.csv')
assert len(passages) == 678
assert len(sentences) == 6275
by_title = defaultdict(list)
for row in sentences:
    by_title[builder.normalized(row['passage_title'])].append({
        'index': int(row['idx']),
        'englishText': builder.clean(row['sentence_en']),
        'turkishText': builder.clean(row['sentence_tr']),
    })
index = json.load(open('assets/content/v1/readings/index.json', encoding='utf-8'))['readings']
assert len(index) == 678
for entry in index:
    item = json.load(open('assets/content/v1/' + entry['file'], encoding='utf-8'))
    expected = sorted(by_title[builder.normalized(entry['title'])], key=lambda value: value['index'])
    assert item['sentences'] == expected
allowed = {
    (source.parent / 'words' / 'passagetr_yds_words_canonical_7500_FINAL.csv').resolve(),
    (source / 'reading_passages.csv').resolve(),
    (source / 'reading_sentences.csv').resolve(),
    (source / 'reading_questions_v1.json').resolve(),
    Path('source_data/canonical/dictionary/dictionary_tr_en.xlsx').resolve(),
    Path('source_data/curated/readings_001_100_curated_v2.json').resolve(),
}
assert {path.resolve() for path in Path('source_data').rglob('*') if path.is_file()} == allowed
''';
    final result = await Process.run(
      'python',
      <String>['-c', script],
      workingDirectory: Directory.current.path,
    );

    expect(result.exitCode, 0, reason: result.stderr.toString());
  });

  test('curated and snapshot question payloads remain separate from body CSV',
      () async {
    const script = r'''
import json

curated = json.load(open('source_data/curated/readings_001_100_curated_v2.json', encoding='utf-8'))
snapshot = json.load(open('source_data/canonical/readings/reading_questions_v1.json', encoding='utf-8'))
assert len(curated) == 100
assert all('sentences' not in item for item in curated)
assert snapshot['schemaVersion'] == 1
assert len(snapshot['derivedQuestions']) == 578
assert {item['sourceNumber'] for item in snapshot['derivedQuestions']} == set(range(101, 679))
''';
    final result = await Process.run(
      'python',
      <String>['-c', script],
      workingDirectory: Directory.current.path,
    );

    expect(result.exitCode, 0, reason: result.stderr.toString());
  });
}
