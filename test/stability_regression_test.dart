import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passagetr_gp/core/local_progress.dart';
import 'package:passagetr_gp/features/tts/student_tts_controller.dart';
import 'package:passagetr_gp/features/tts/student_tts_engine.dart';
import 'package:passagetr_gp/repositories/local_progress_repository.dart';
import 'package:passagetr_gp/repositories/static_content_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('restore öncesi favori kaybı olmaz: kayıtlar birleştirilir', () async {
    SharedPreferences.setMockInitialValues(
      <String, Object>{'passagetr.favoriteWordIds.v1': <String>['a']},
    );
    final controller = LocalProgressController(LocalProgressRepository());
    // Restore henüz bitmeden yapılan değişiklik korunmalı.
    controller.toggleFavoriteWord('b');
    await controller.restoreFuture;
    expect(controller.state.isLoaded, isTrue);
    expect(controller.state.favoriteWordIds, containsAll(<String>['a', 'b']));
    controller.dispose();
  });

  test('başarısız asset yüklemesi cachede kalmaz, tekrar deneme çalışır',
      () async {
    final bundle = _FlakyBundle(failures: 1);
    final repository = StaticContentRepository(bundle: bundle);
    // İlk deneme geçici hatayla düşer.
    await expectLater(repository.loadPacks(), throwsA(isA<Exception>()));
    // Tekrar dene gerçekten yeniden yükler.
    final packs = await repository.loadPacks();
    expect(packs, isEmpty);
  });

  test('eski TTS session statei değiştirmez ve stop gerçekten durdurur',
      () async {
    final engine = _BlockingTtsEngine();
    final controller = StudentTtsController(engine: engine);
    final first = controller.playSentence(
      readingId: 'reading-1',
      sentenceIndex: 1,
      text: 'First.',
    );
    await _waitUntil(() => engine.spokenTexts.length == 1);
    // Yeni oynatma + stop sonrası eski session statei ezemez.
    final second = controller.playSentence(
      readingId: 'reading-1',
      sentenceIndex: 2,
      text: 'Second.',
    );
    await _waitUntil(() => engine.spokenTexts.length == 2);
    await controller.stop();
    expect(controller.state.isSpeaking, isFalse);
    expect(controller.state.activeSentenceIndex, isNull);
    engine.completeAll();
    await Future.wait(<Future<StudentTtsActionResult>>[first, second]);
    expect(controller.state.isSpeaking, isFalse);
    controller.dispose();
  });
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  throw StateError('Timed out waiting for condition.');
}

class _BlockingTtsEngine implements StudentTtsEngine {
  final List<Completer<void>> _speaks = <Completer<void>>[];
  final List<String> spokenTexts = <String>[];

  @override
  Future<void> dispose() async {}

  @override
  Future<StudentTtsAvailability> ensureInitialized() async =>
      StudentTtsAvailability.available;

  @override
  Future<void> speak(String text, {String? languageCode}) {
    spokenTexts.add(text);
    final completer = Completer<void>();
    _speaks.add(completer);
    return completer.future;
  }

  @override
  Future<void> stop() async {}

  void completeAll() {
    for (final completer in _speaks) {
      if (!completer.isCompleted) completer.complete();
    }
  }
}

class _FlakyBundle extends AssetBundle {
  _FlakyBundle({required this.failures});

  int failures;
  final Map<String, int> calls = <String, int>{};

  String _payload(String key) {
    if (key.endsWith('manifest.json')) {
      return jsonEncode(<String, Object?>{
        'counts': <String, Object?>{
          'words': 9000,
          'readings': 678,
          'sentences': 6275,
        },
        'packs': <Object?>[],
        'readingsIndex': 'readings.json',
        'wordsIndex': 'words.json',
      });
    }
    if (key.endsWith('readings.json')) {
      return jsonEncode(<String, Object?>{
        'readings': List<Object?>.generate(
          678,
          (index) => <String, Object?>{
            'id': 'reading-$index',
            'packId': 'pack',
            'title': 'Title $index',
            'sentenceCount': 9,
            'level': 'B1',
            'file': 'items/reading-$index.json',
          },
        ),
      });
    }
    throw StateError('Beklenmeyen asset: $key');
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    calls[key] = (calls[key] ?? 0) + 1;
    if (failures > 0) {
      failures -= 1;
      throw StateError('Geçici yükleme hatası');
    }
    return _payload(key);
  }

  @override
  Future<ByteData> load(String key) =>
      throw UnimplementedError('Yalnız loadString desteklenir.');
}
