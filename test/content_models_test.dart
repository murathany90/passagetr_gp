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

  test('reading detail parses its separate enrichment layer', () {
    final detail = ReadingDetail.fromJson(<String, Object?>{
      'id': 'reading-1',
      'packId': 'pack-1',
      'title': '001-Source title (Kaynak başlık)',
      'sentences': <Object?>[
        <String, Object?>{
          'index': 1,
          'englishText': 'A real source sentence.',
          'turkishText': 'Gerçek bir kaynak cümle.',
        },
      ],
      'enrichment': <String, Object?>{
        'displayTitle': 'Source title',
        'turkishTitle': 'Kaynak başlık',
        'wordCount': 4,
        'estimatedReadingMinutes': 1,
        'focusWordIds': <String>['word-1'],
        'summary': 'A real source sentence.',
        'questions': <Object?>[
          <String, Object?>{
            'id': 'question-1',
            'sortOrder': 1,
            'question': 'Complete: A real ____ sentence.',
            'options': <String>['source', 'other', 'wrong', 'choice'],
            'correctOptionIndex': 0,
            'explanation': 'Sentence 1.',
          },
        ],
      },
    });

    expect(detail.passage.displayTitle, 'Source title');
    expect(detail.passage.wordCount, 4);
    expect(detail.focusWordIds, <String>['word-1']);
    expect(detail.questions, hasLength(1));
  });
}
