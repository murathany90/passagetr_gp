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
      'source_data/quality/reading_content_repairs_101_300_v4.json',
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
      'source_data/reports/reading_101_300_language_polish_audit_v4.json',
    );
    final languageSummary = languageAudit['summary']! as Map<String, Object?>;
    expect(languageSummary['retainedRepairSentencesAudited'], 108);
    expect(languageSummary['sentencesRewritten'], 5);

    final rangeOverlay = _json(
      'source_data/quality/reading_content_repairs_301_500_v2.json',
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

    final finalRangeOverlay = _json(
      'source_data/quality/reading_content_repairs_501_678_v1.json',
    );
    final finalRangeRepairs = finalRangeOverlay['repairs']! as List<Object?>;
    expect(finalRangeRepairs, hasLength(8));
    final firstFinalRepair = finalRangeRepairs
        .cast<Map<String, Object?>>()
        .singleWhere((repair) => repair['sourceNumber'] == 501);
    expect(firstFinalRepair['appendSentences'], hasLength(2));
    final finalRangeAudit = _json(
      'source_data/reports/reading_501_678_editorial_audit_v1.json',
    );
    final finalRangeSummary =
        finalRangeAudit['summary']! as Map<String, Object?>;
    expect(finalRangeSummary['total'], 178);
    expect(finalRangeSummary['safeToExpand'], 8);
    expect(finalRangeSummary['sourceMissing'], 4);

    final finalQuality = _json(
      'source_data/reports/reading_quality_final_v1.json',
    );
    final finalSummary = finalQuality['summary']! as Map<String, Object?>;
    expect(finalSummary['totalReadings'], 678);
    expect(finalSummary['totalSentences'], 6275);
    expect(finalSummary['fullTrCoverage'], isTrue);

    final manifest = _json('assets/content/v1/manifest.json');
    final quality = Map<String, Object?>.from(
      manifest['productionEditorialQuality']! as Map,
    );
    for (final key in <String>[
      'repairs101To300V4',
      'repairs301To500V2',
      'repairs501To678V1',
      'allProductionOverlays',
    ]) {
      final summary = Map<String, Object?>.from(quality[key]! as Map);
      expect(summary['forbiddenTemplateOccurrences'], 0);
      expect(summary['exactDuplicateOccurrences'], 0);
      expect(summary['semanticRepetitionCandidates'], 0);
      expect(summary['canonicalSentenceEmbeddingOccurrences'], 0);
      expect(summary['missingBilingualOccurrences'], 0);
    }
    final questionIntegrity =
        Map<String, Object?>.from(manifest['readingQuestionIntegrity']! as Map);
    expect(questionIntegrity['payloadSha256'], isA<String>());
    expect((questionIntegrity['payloadSha256']! as String).length, 64);
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

  test(
      'canonical language corrections are source-bound and leave curated data immutable',
      () {
    final overlay = _json(
      'source_data/quality/reading_canonical_language_corrections_v1.json',
    );
    final corrections = overlay['corrections']! as List<Object?>;
    expect(corrections, hasLength(30));

    final canonicalAudit = _json(
      'source_data/reports/reading_canonical_language_audit_v1.json',
    );
    final summary = canonicalAudit['summary']! as Map<String, Object?>;
    expect(summary['canonicalSentencesAudited'], 4624);
    expect(summary['critical'], 6);

    final manualOverlay = _json(
      'source_data/quality/reading_canonical_language_corrections_101_300_v2.json',
    );
    final manualCorrections = manualOverlay['corrections']! as List<Object?>;
    expect(manualCorrections, hasLength(29));
    expect(
      manualCorrections.cast<Map<String, Object?>>().map(
            (correction) => correction['sourceNumber'] as int,
          ),
      everyElement(inInclusiveRange(101, 300)),
    );

    final manualReview = _json(
      'source_data/reports/reading_canonical_editorial_review_101_300_v1.json',
    );
    final manualSummary = manualReview['summary']! as Map<String, Object?>;
    expect(manualSummary['readingsReviewed'], 200);
    expect(manualSummary['sentencePairsReviewed'], 1687);
    expect(manualSummary['manualReviewRemaining'], 0);
    expect(manualSummary['sourceMissingReadings'], <int>[118, 175, 196, 226, 244, 269]);

    final reviewedReadings = manualReview['reviewedReadings']! as List<Object?>;
    expect(reviewedReadings, hasLength(200));
    expect(
      reviewedReadings.cast<Map<String, Object?>>().every(
            (record) => record['reviewed'] == true,
          ),
      isTrue,
    );

    final index = _json('assets/content/v1/readings/index.json');
    final entry = (index['readings']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .singleWhere((item) => item['sourceNumber'] == '513');
    final napster = _json('assets/content/v1/${entry['file']}');
    final sentence = (napster['sentences']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .singleWhere((item) => item['index'] == 6);
    expect(sentence['englishText'],
        contains('contributory copyright infringement'));

    final marsEntry = (index['readings']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .singleWhere((item) => item['sourceNumber'] == '110');
    final mars = _json('assets/content/v1/${marsEntry['file']}');
    final marsSentence = (mars['sentences']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .singleWhere((item) => item['index'] == 4);
    expect(marsSentence['englishText'], contains('rotates once every twenty-four hours'));

    final curatedReadings = jsonDecode(File(
      'source_data/curated/readings_001_100_curated_v2.json',
    ).readAsStringSync()) as List<Object?>;
    final firstCurated = Map<String, Object?>.from(
      curatedReadings.first as Map,
    );
    final curatedEntry = (index['readings']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .singleWhere((item) => item['sourceNumber'] == '001');
    final generatedCurated = _json('assets/content/v1/${curatedEntry['file']}');
    final expectedSentence = Map<String, Object?>.from(
      (firstCurated['sentences']! as List<Object?>).first as Map,
    );
    final generatedSentence = Map<String, Object?>.from(
      (generatedCurated['sentences']! as List<Object?>).first as Map,
    );
    expect(generatedSentence['englishText'], expectedSentence['en']);
    expect(generatedSentence['turkishText'], expectedSentence['tr']);
  });
}

Map<String, Object?> _json(String path) =>
    Map<String, Object?>.from(jsonDecode(File(path).readAsStringSync()) as Map);
