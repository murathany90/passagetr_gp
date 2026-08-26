import 'package:flutter_test/flutter_test.dart';
import 'package:passagetr_gp/features/readings/reading_models.dart';
import 'package:passagetr_gp/models/content_models.dart';

void main() {
  test('word JSON preserves required public fields', () {
    final word = WordEntry.fromJson(<String, Object?>{
      'id': 'word-1',
      'packId': 'pack-1',
      'enWord': 'learn',
      'trMeaning': 'öğrenmek',
      'pos': 'v.',
      'exampleEn': 'We learn.',
      'exampleTr': null,
      'synonymsRaw': null,
      'antonymsRaw': null,
      'notes': null,
      'level': 'A1',
      'tags': <String>['general'],
    });
    expect(word.enWord, 'learn');
    expect(word.tags, <String>['general']);
  });

  test('reading token normalization strips edge punctuation', () {
    expect(normalizeDictionaryQuery('“Ocean,”'), 'ocean');
  });
}
