import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passagetr_gp/core/app_theme.dart';
import 'package:passagetr_gp/core/content_providers.dart';
import 'package:passagetr_gp/core/local_progress.dart';
import 'package:passagetr_gp/features/readings/reading_detail_page.dart';
import 'package:passagetr_gp/features/readings/readings_page.dart';
import 'package:passagetr_gp/features/dictionary/dictionary_page.dart';
import 'package:passagetr_gp/features/tts/student_tts_engine.dart';
import 'package:passagetr_gp/features/words/words_page.dart';
import 'package:passagetr_gp/models/content_models.dart';
import 'package:passagetr_gp/repositories/local_progress_repository.dart';
import 'package:passagetr_gp/repositories/static_content_repository.dart';

void main() {
  const pack = ContentPack(id: 'pack-a', name: 'Temel', wordCount: 2);
  const firstWord = WordEntry(
    id: 'word-a',
    packId: 'pack-a',
    enWord: 'access',
    trMeaning: 'erişim',
    pos: 'n.',
    exampleEn: 'Access is useful.',
    level: 'B1',
  );
  const secondWord = WordEntry(
    id: 'word-b',
    packId: 'pack-a',
    enWord: 'bridge',
    trMeaning: 'köprü',
    pos: 'n.',
    exampleEn: 'The bridge is old.',
    level: 'B2',
  );
  const passage = ReadingPassage(
    id: 'reading-a',
    packId: 'pack-a',
    title: 'Kısa okuma',
    sentenceCount: 2,
    level: 'B1',
    category: 'Science',
  );
  const detail = ReadingDetail(
    passage: passage,
    sentences: <ReadingSentence>[
      ReadingSentence(
        index: 1,
        englishText: 'Access to knowledge changes lives.',
        turkishText: 'Bilgiye erişim hayatları değiştirir.',
      ),
      ReadingSentence(
        index: 2,
        englishText: 'A bridge connects people.',
        turkishText: 'Bir köprü insanları birbirine bağlar.',
      ),
    ],
    focusWordIds: <String>[],
    questions: <ReadingQuestion>[
      ReadingQuestion(
        id: 'question-a',
        sortOrder: 1,
        question: 'What does the passage say?',
        questionTr: 'What does the passage say in Turkish?',
        options: <String>[
          'Knowledge changes lives.',
          'A bridge is closed.',
          'The library is empty.',
          'No answer is given.',
        ],
        optionsTr: <String>[
          'Knowledge changes lives in Turkish.',
          'A bridge is closed in Turkish.',
          'The library is empty in Turkish.',
          'No answer is given in Turkish.',
        ],
        correctOptionIndex: 0,
        answerEn: 'Knowledge changes lives.',
        answerTr: 'Knowledge changes lives in Turkish.',
        explanation: 'The first sentence supports this answer.',
        explanationTr: 'The first sentence supports this answer in Turkish.',
        evidenceSentenceIndexes: <int>[1],
      ),
    ],
  );
  final repository = _FixtureRepository(
    packs: const <ContentPack>[pack],
    words: const <WordEntry>[firstWord, secondWord],
    readings: const <ReadingPassage>[passage],
    detail: detail,
  );

  Widget app(Widget child) => ProviderScope(
        overrides: <Override>[
          staticContentRepositoryProvider.overrideWithValue(repository),
          localProgressRepositoryProvider.overrideWithValue(_MemoryProgress()),
          studentTtsEngineProvider.overrideWithValue(_SilentTtsEngine()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: child),
        ),
      );

  testWidgets('390px Words opens without overflow and search filters',
      (tester) async {
    await _setPhoneSize(tester);
    await tester.pumpWidget(app(const WordsPage()));
    await _pumpContent(tester);

    expect(find.text('2 sonuç'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'access');
    await tester.pump();
    expect(find.text('1 sonuç'), findsOneWidget);
    expect(find.text('erişim'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('390px Readings opens without overflow', (tester) async {
    await _setPhoneSize(tester);
    await tester.pumpWidget(app(const ReadingsPage()));
    await _pumpContent(tester);

    expect(find.text('1 sonuç'), findsOneWidget);
    expect(find.text('Kısa okuma'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('390px Reading Detail hides and reveals the real translation',
      (tester) async {
    await _setPhoneSize(tester);
    await tester
        .pumpWidget(app(const ReadingDetailPage(readingId: 'reading-a')));
    await _pumpContent(tester);

    expect(find.text('Access'), findsOneWidget);
    expect(find.text('Bilgiye erişim hayatları değiştirir.'), findsNothing);
    final card = find.byKey(const ValueKey<String>('sentence-card-1'));
    final origin = tester.getTopLeft(card);
    await tester.tapAt(origin + const Offset(5, 5));
    await tester.pump();
    expect(find.text('Bilgiye erişim hayatları değiştirir.'), findsOneWidget);
    expect(find.text('Bir köprü insanları birbirine bağlar.'), findsNothing);
    await tester.tap(find.text('Tüm çevirileri göster'));
    await tester.pump();
    expect(find.text('Tümünü gizle'), findsOneWidget);
    expect(find.text('Bir köprü insanları birbirine bağlar.'), findsOneWidget);
    await tester.tap(find.text('Tümünü gizle'));
    await tester.pump();
    expect(find.text('Bilgiye erişim hayatları değiştirir.'), findsNothing);
    expect(find.text('Bir köprü insanları birbirine bağlar.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('390px Dictionary opens without overflow', (tester) async {
    await _setPhoneSize(tester);
    await tester.pumpWidget(app(const DictionaryPage()));
    await tester.pump();

    expect(find.text('Sözlük'), findsOneWidget);
    expect(find.text('İngilizce kelime ara...'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _setPhoneSize(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _pumpContent(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

class _FixtureRepository extends StaticContentRepository {
  _FixtureRepository({
    required this.packs,
    required this.words,
    required this.readings,
    required this.detail,
  }) : super(bundle: _MissingAssetBundle());

  final List<ContentPack> packs;
  final List<WordEntry> words;
  final List<ReadingPassage> readings;
  final ReadingDetail detail;

  @override
  Future<List<ContentPack>> loadPacks() async => packs;

  @override
  Future<List<WordEntry>> loadWords() async => words;

  @override
  Future<List<ReadingPassage>> loadReadings() async => readings;

  @override
  Future<ReadingDetail> loadReading(String readingId) async => detail;
}

class _MemoryProgress extends LocalProgressRepository {
  @override
  Future<LocalProgressSnapshot> load() async =>
      const LocalProgressSnapshot(isLoaded: true);

  @override
  Future<void> saveCompletedReadingIds(Set<String> ids) async {}

  @override
  Future<void> saveFavoriteWordIds(Set<String> ids) async {}

  @override
  Future<void> saveKnownWordIds(Set<String> ids) async {}

  @override
  Future<void> saveReadingFilters({String? level, String? category}) async {}

  @override
  Future<void> saveWordFilters({String? packId, String? level}) async {}
}

class _MissingAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) =>
      Future<ByteData>.error(FileSystemException('Missing asset', key));
}

class _SilentTtsEngine implements StudentTtsEngine {
  @override
  Future<void> dispose() async {}

  @override
  Future<StudentTtsAvailability> ensureInitialized() async =>
      StudentTtsAvailability.available;

  @override
  Future<void> speak(String text, {String? languageCode}) async {}

  @override
  Future<void> stop() async {}
}
