import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/content_models.dart';

import 'student_tts_engine.dart';

class StudentTtsController extends StateNotifier<StudentTtsState> {
  StudentTtsController({required StudentTtsEngine engine})
      : _engine = engine,
        super(const StudentTtsState.initial());

  final StudentTtsEngine _engine;
  int _sessionId = 0;

  Future<StudentTtsActionResult> playWord({
    required WordEntry word,
    String? readingId,
  }) {
    return _playSingle(
      target: StudentTtsTarget.word,
      text: word.enWord,
      readingId: readingId,
      wordId: word.id,
    );
  }

  Future<StudentTtsActionResult> playSentence({
    required String readingId,
    required int sentenceIndex,
    required String text,
  }) {
    return _playSingle(
      target: StudentTtsTarget.sentence,
      text: text,
      readingId: readingId,
      sentenceIndex: sentenceIndex,
    );
  }

  Future<StudentTtsActionResult> playPassage({
    required String readingId,
    required List<StudentTtsPassageSegment> segments,
  }) async {
    final filteredSegments = segments
        .where((segment) => segment.text.trim().isNotEmpty)
        .toList(growable: false);
    if (filteredSegments.isEmpty) {
      if (mounted) {
        state = _idleState(errorMessage: 'Metin simdi okunamadi.');
      }
      return StudentTtsActionResult.failed;
    }

    final availability = await _preparePlayback(
      target: StudentTtsTarget.passage,
      readingId: readingId,
      sentenceIndex: filteredSegments.first.sentenceIndex,
    );
    if (availability != StudentTtsAvailability.available) {
      return StudentTtsActionResult.unavailable;
    }

    final session = _sessionId;
    try {
      for (final segment in filteredSegments) {
        if (!mounted) {
          return StudentTtsActionResult.stopped;
        }
        if (session != _sessionId) {
          return StudentTtsActionResult.stopped;
        }

        state = state.copyWith(
          isInitializing: false,
          isSpeaking: true,
          activeTarget: StudentTtsTarget.passage,
          activeReadingId: readingId,
          activeSentenceIndex: segment.sentenceIndex,
          clearError: true,
        );
        await _engine.speak(segment.text);
      }
    } catch (_) {
      if (mounted && session == _sessionId) {
        state = _idleState(errorMessage: 'Metin simdi okunamadi.');
      }
      return StudentTtsActionResult.failed;
    }

    if (mounted && session == _sessionId) {
      state = _idleState();
    }
    return StudentTtsActionResult.started;
  }

  Future<StudentTtsActionResult> stop() async {
    if (!mounted) {
      return StudentTtsActionResult.stopped;
    }

    _sessionId += 1;
    final availability = state.availability;
    await _engine.stop();
    if (!mounted) {
      return StudentTtsActionResult.stopped;
    }
    state = StudentTtsState(
      availability: availability,
      isInitializing: false,
      isSpeaking: false,
      activeTarget: null,
      activeReadingId: null,
      activeSentenceIndex: null,
      activeWordId: null,
      errorMessage: null,
    );
    return StudentTtsActionResult.stopped;
  }

  Future<void> stopIfMatching({
    StudentTtsTarget? target,
    String? readingId,
    int? sentenceIndex,
    String? wordId,
  }) async {
    if (!_matchesCurrentTarget(
      target: target,
      readingId: readingId,
      sentenceIndex: sentenceIndex,
      wordId: wordId,
    )) {
      return;
    }

    await stop();
  }

  Future<StudentTtsActionResult> _playSingle({
    required StudentTtsTarget target,
    required String text,
    String? readingId,
    int? sentenceIndex,
    String? wordId,
  }) async {
    final availability = await _preparePlayback(
      target: target,
      readingId: readingId,
      sentenceIndex: sentenceIndex,
      wordId: wordId,
    );
    if (availability != StudentTtsAvailability.available) {
      return StudentTtsActionResult.unavailable;
    }

    final session = _sessionId;
    if (!mounted) {
      return StudentTtsActionResult.stopped;
    }
    state = state.copyWith(
      isInitializing: false,
      isSpeaking: true,
      activeTarget: target,
      activeReadingId: readingId,
      activeSentenceIndex: sentenceIndex,
      activeWordId: wordId,
      clearError: true,
    );

    try {
      await _engine.speak(text);
    } catch (_) {
      if (mounted && session == _sessionId) {
        state = _idleState(errorMessage: 'Metin simdi okunamadi.');
      }
      return StudentTtsActionResult.failed;
    }

    if (mounted && session == _sessionId) {
      state = _idleState();
    }
    return StudentTtsActionResult.started;
  }

  Future<StudentTtsAvailability> _preparePlayback({
    required StudentTtsTarget target,
    String? readingId,
    int? sentenceIndex,
    String? wordId,
  }) async {
    if (!mounted) {
      return StudentTtsAvailability.unsupported;
    }

    _sessionId += 1;
    final session = _sessionId;
    state = state.copyWith(
      isInitializing: true,
      isSpeaking: false,
      activeTarget: target,
      activeReadingId: readingId,
      activeSentenceIndex: sentenceIndex,
      activeWordId: wordId,
      clearError: true,
    );

    await _engine.stop();
    if (!mounted) {
      return StudentTtsAvailability.unsupported;
    }
    if (session != _sessionId) {
      return state.availability;
    }

    final availability = await _engine.ensureInitialized();
    if (!mounted) {
      return availability;
    }
    if (session != _sessionId) {
      return availability;
    }

    if (availability != StudentTtsAvailability.available) {
      state = StudentTtsState(
        availability: availability,
        isInitializing: false,
        isSpeaking: false,
        activeTarget: null,
        activeReadingId: null,
        activeSentenceIndex: null,
        activeWordId: null,
        errorMessage: _messageForAvailability(availability),
      );
      return availability;
    }

    state = state.copyWith(
      availability: availability,
      isInitializing: false,
      clearError: true,
    );
    return availability;
  }

  StudentTtsState _idleState({String? errorMessage}) {
    return StudentTtsState(
      availability: state.availability,
      isInitializing: false,
      isSpeaking: false,
      activeTarget: null,
      activeReadingId: null,
      activeSentenceIndex: null,
      activeWordId: null,
      errorMessage: errorMessage,
    );
  }

  bool _matchesCurrentTarget({
    StudentTtsTarget? target,
    String? readingId,
    int? sentenceIndex,
    String? wordId,
  }) {
    if (target != null && state.activeTarget != target) {
      return false;
    }
    if (readingId != null && state.activeReadingId != readingId) {
      return false;
    }
    if (sentenceIndex != null && state.activeSentenceIndex != sentenceIndex) {
      return false;
    }
    if (wordId != null && state.activeWordId != wordId) {
      return false;
    }
    return state.isSpeaking || state.isInitializing;
  }

  String _messageForAvailability(StudentTtsAvailability availability) {
    return switch (availability) {
      StudentTtsAvailability.noEnglishVoice => kIsWeb
          ? 'Bu tarayici TTS desteklemiyor.'
          : 'Bu cihazda English TTS kullanilamiyor.',
      StudentTtsAvailability.unsupported => kIsWeb
          ? 'Bu tarayici TTS desteklemiyor.'
          : 'Bu cihazda English TTS kullanilamiyor.',
      StudentTtsAvailability.available ||
      StudentTtsAvailability.unknown =>
        'Metin simdi okunamadi.',
    };
  }
}
