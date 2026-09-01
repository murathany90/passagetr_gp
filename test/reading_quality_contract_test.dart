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
      'source_data/quality/reading_content_repairs_101_300_v3.json',
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

    final languageAudit = _json(
      'source_data/reports/reading_101_300_language_polish_audit_v3.json',
    );
    final languageSummary = languageAudit['summary']! as Map<String, Object?>;
    expect(languageSummary['retainedRepairSentencesAudited'], 108);
    expect(languageSummary['sentencesRewritten'], greaterThan(0));

    final rangeOverlay = _json(
      'source_data/quality/reading_content_repairs_301_500_v1.json',
    );
    final rangeRepairs = rangeOverlay['repairs']! as List<Object?>;
    expect(rangeRepairs, hasLength(8));
    final expanded = rangeRepairs.cast<Map<String, Object?>>().singleWhere(
          (repair) => repair['sourceNumber'] == 304,
        );
    expect((expanded['appendSentences']! as List<Object?>), hasLength(2));
    final expandedItem = _json(
      'assets/content/v1/readings/items/b992bb3e-90a8-5500-b1ed-1142fb0f481f.json',
    );
    final expandedQuestions = Map<String, Object?>.from(
      expandedItem['enrichment']! as Map,
    )['questions']! as List<Object?>;
    for (final question in expandedQuestions.cast<Map<String, Object?>>()) {
      final text = question['question']! as String;
      expect(text, isNot(contains('Complete sentence 9')));
      expect(text, isNot(contains('Complete sentence 10')));
    }

    final rangeAudit = _json(
      'source_data/reports/reading_301_500_editorial_audit_v1.json',
    );
    final rangeSummary = rangeAudit['summary']! as Map<String, Object?>;
    expect(rangeSummary['safeToExpand'], 8);
    expect(rangeSummary['sourceMissing'], 8);

    final manifest = _json('assets/content/v1/manifest.json');
    final quality = Map<String, Object?>.from(
      manifest['productionEditorialQuality']! as Map,
    );
    for (final key in <String>['repairs101To300V3', 'repairs301To500V1']) {
      final summary = Map<String, Object?>.from(quality[key]! as Map);
      expect(summary['forbiddenTemplateOccurrences'], 0);
      expect(summary['exactDuplicateOccurrences'], 0);
      expect(summary['semanticRepetitionCandidates'], 0);
      expect(summary['canonicalSentenceEmbeddingOccurrences'], 0);
      expect(summary['missingBilingualOccurrences'], 0);
    }
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
