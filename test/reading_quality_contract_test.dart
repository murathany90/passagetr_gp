import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('quality overlays are reflected in generated reading content and audits',
      () {
    final item = _json(
      'assets/content/v1/readings/items/7ac99bbb-7826-5d04-ba80-ec89dcda1758.json',
    );
    final sentences = item['sentences']! as List<Object?>;
    final enrichment = item['enrichment']! as Map<String, Object?>;
    final questions = enrichment['questions']! as List<Object?>;
    final lengthAudit =
        _json('source_data/reports/reading_length_audit_v1.json');
    final records = lengthAudit['readings']! as List<Object?>;
    final repaired = records.cast<Map<String, Object?>>().singleWhere(
          (record) => record['sourceNumber'] == 102,
        );

    expect(sentences, hasLength(10));
    expect(
      questions.cast<Map<String, Object?>>().map(
            (question) => question['questionCategory'],
          ),
      everyElement('vocabulary_practice'),
    );
    expect(repaired['contentRepairApplied'], isTrue);
    expect(repaired['qualityBand'], isNot('critical_short'));

    final editorialOverlay = _json(
      'source_data/quality/reading_content_repairs_101_300_v2.json',
    );
    final repairs = editorialOverlay['repairs']! as List<Object?>;
    final goodRepair = repairs.cast<Map<String, Object?>>().singleWhere(
          (repair) => repair['sourceNumber'] == 103,
        );
    expect(repairs, hasLength(52));
    expect(goodRepair['appendSentences'], isA<List<Object?>>());
    expect(
      (goodRepair['appendSentences']! as List<Object?>).length,
      2,
    );
    final goodRecord = records.cast<Map<String, Object?>>().singleWhere(
          (record) => record['sourceNumber'] == 103,
        );
    expect(goodRecord['contentRepairApplied'], isTrue);
    expect(goodRecord['qualityBand'], isNot('critical_short'));

    final editorialAudit = _json(
      'source_data/reports/reading_repairs_101_300_editorial_audit_v2.json',
    );
    final summary = editorialAudit['summary']! as Map<String, Object?>;
    final auditReadings = editorialAudit['readings']! as List<Object?>;
    final insufficient = auditReadings.cast<Map<String, Object?>>().singleWhere(
          (record) => record['sourceNumber'] == 101,
        );
    expect(summary['forbiddenTemplateOccurrencesAfter'], 0);
    expect(insufficient['acceptedCount'], 0);
    expect(
      insufficient['editorialStatus'],
      'insufficient_source_for_safe_expansion',
    );
  });

  test('source baseline v2 changes when canonical content changes in memory',
      () async {
    const script = r'''
import json
import sys
sys.path.insert(0, 'tools')
import build_static_content as builder
import validate_static_content as validator

baseline = json.load(open('source_data/baselines/readings_101_678_source_baseline_v2.json', encoding='utf-8'))
passages = validator.canonical_passages()
assert builder.canonical_source_baseline_payload(passages) == baseline
target = next(passage for passage in passages.values() if builder.source_number_for(passage) == 101)
target['sentences'][0]['englishText'] += ' changed only in memory'
assert builder.canonical_source_baseline_payload(passages)['canonicalContentSha256'] != baseline['canonicalContentSha256']
''';
    final result = await Process.run(
      'python',
      <String>['-c', script],
      workingDirectory: Directory.current.path,
    );

    expect(result.exitCode, 0, reason: result.stderr.toString());
  });
}

Map<String, Object?> _json(String path) =>
    Map<String, Object?>.from(jsonDecode(File(path).readAsStringSync()) as Map);
