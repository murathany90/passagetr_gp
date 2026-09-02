import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passagetr_gp/core/app_theme.dart';
import 'package:passagetr_gp/core/content_providers.dart';
import 'package:passagetr_gp/features/home/landing_page.dart';
import 'package:passagetr_gp/features/tts/student_tts_engine.dart';
import 'package:passagetr_gp/repositories/static_content_repository.dart';

void main() {
  final repository = StaticContentRepository(bundle: _FileAssetBundle());

  Widget app(
    Widget child, {
    StaticContentRepository? repositoryOverride,
  }) =>
      ProviderScope(
        overrides: <Override>[
          staticContentRepositoryProvider.overrideWithValue(
            repositoryOverride ?? repository,
          ),
          studentTtsEngineProvider.overrideWithValue(_SilentTtsEngine()),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: child),
      );

  test('public static repository loads every accepted content record',
      () async {
    final packs = await repository.loadPacks();
    final words = await repository.loadWords();
    final readings = await repository.loadReadings();
    final detail = await repository.loadReading(readings.first.id);

    expect(packs, isNotEmpty);
    expect(words, hasLength(7500));
    expect(words.map((word) => word.id).toSet(), hasLength(7500));
    expect(readings, hasLength(678));
    expect(detail.sentences, isNotEmpty);
    expect(detail.sentences.first.englishText, isNotEmpty);
  });

  test('word search and pack filtering use real records', () async {
    final words = await repository.loadWords();
    final packs = await repository.loadPacks();
    final target = words.firstWhere(
      (word) => words.where((item) => item.enWord == word.enWord).length == 1,
    );
    final searchResults = words
        .where((word) => '${word.enWord} ${word.trMeaning} ${word.pos}'
            .toLowerCase()
            .contains(target.enWord.toLowerCase()))
        .toList(growable: false);
    final selectedPack = packs.firstWhere((pack) => pack.wordCount > 0);
    final packResults = words
        .where((word) => word.packId == selectedPack.id)
        .toList(growable: false);

    expect(searchResults, isNotEmpty);
    expect(packResults, hasLength(selectedPack.wordCount));
  });

  test('missing assets surface DATA_LOAD_ERROR without sample fallback',
      () async {
    final missing = StaticContentRepository(bundle: _MissingAssetBundle());

    await expectLater(
      missing.loadWords(),
      throwsA(
        isA<StaticContentException>().having(
          (error) => error.toString(),
          'message',
          startsWith('DATA_LOAD_ERROR:'),
        ),
      ),
    );
  });

  testWidgets('home opens at a 390 px viewport without overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(app(const LandingPage()));
    await tester.pump();

    expect(find.text('Kelime'), findsOneWidget);
    expect(find.text('Okuma'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('readings index and real EN/TR detail use bundled records', () async {
    final readings = await repository.loadReadings();
    final detail = await repository.loadReading(readings.first.id);
    expect(readings, hasLength(678));
    expect(readings.first.title, isNotEmpty);
    expect(detail.sentences.first.englishText, isNotEmpty);
    expect(
      detail.sentences
          .where((sentence) => sentence.turkishText?.isNotEmpty == true),
      isNotEmpty,
    );
  });
}

class _FileAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bytes = await File(key).readAsBytes();
    return ByteData.sublistView(bytes);
  }
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
