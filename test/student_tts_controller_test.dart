import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:passagetr_gp/features/tts/student_tts_controller.dart';
import 'package:passagetr_gp/features/tts/student_tts_engine.dart';

void main() {
  test('EN and TR sentence playback keep separate active language state',
      () async {
    final engine = _BlockingTtsEngine();
    final controller = StudentTtsController(engine: engine);

    final english = controller.playSentence(
      readingId: 'reading-1',
      sentenceIndex: 1,
      text: 'English sentence.',
    );
    await _waitUntil(() => engine.languageCodes.length == 1);
    expect(controller.state.activeTarget, StudentTtsTarget.sentence);
    expect(controller.state.activeLanguageCode, 'en-US');
    expect(controller.state.isSpeaking, isTrue);

    final turkish = controller.playTurkishSentence(
      readingId: 'reading-1',
      sentenceIndex: 1,
      text: 'Türkçe cümle.',
    );
    await _waitUntil(() => engine.languageCodes.length == 2);
    expect(engine.stopCount, 2);
    expect(controller.state.activeTarget, StudentTtsTarget.sentence);
    expect(controller.state.activeLanguageCode, 'tr-TR');
    expect(controller.state.isSpeaking, isTrue);

    engine.completeAll();
    await Future.wait<StudentTtsActionResult>(<Future<StudentTtsActionResult>>[
      english,
      turkish,
    ]);
    expect(controller.state.isSpeaking, isFalse);
    expect(controller.state.activeLanguageCode, isNull);
    controller.dispose();
  });

  test('passage playback remains an English passage target', () async {
    final engine = _BlockingTtsEngine();
    final controller = StudentTtsController(engine: engine);
    final playback = controller.playPassage(
      readingId: 'reading-1',
      segments: const <StudentTtsPassageSegment>[
        StudentTtsPassageSegment(sentenceIndex: 1, text: 'First sentence.'),
        StudentTtsPassageSegment(sentenceIndex: 2, text: 'Second sentence.'),
      ],
    );

    await _waitUntil(() => engine.languageCodes.length == 1);
    expect(controller.state.activeTarget, StudentTtsTarget.passage);
    expect(controller.state.activeLanguageCode, 'en-US');
    engine.completeNext();
    await _waitUntil(() => engine.languageCodes.length == 2);
    engine.completeNext();
    await playback;
    expect(controller.state.isSpeaking, isFalse);
    controller.dispose();
  });
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  throw StateError('Timed out waiting for TTS playback.');
}

class _BlockingTtsEngine implements StudentTtsEngine {
  final List<Completer<void>> _speaks = <Completer<void>>[];
  final List<String?> languageCodes = <String?>[];
  var stopCount = 0;

  @override
  Future<void> dispose() async {}

  @override
  Future<StudentTtsAvailability> ensureInitialized() async =>
      StudentTtsAvailability.available;

  @override
  Future<void> speak(String text, {String? languageCode}) {
    languageCodes.add(languageCode);
    final completer = Completer<void>();
    _speaks.add(completer);
    return completer.future;
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }

  void completeNext() {
    final pending = _speaks.firstWhere((completer) => !completer.isCompleted);
    pending.complete();
  }

  void completeAll() {
    for (final completer in _speaks) {
      if (!completer.isCompleted) completer.complete();
    }
  }
}
