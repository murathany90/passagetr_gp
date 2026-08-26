import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

enum StudentTtsTarget { word, sentence, passage }

enum StudentTtsAvailability { unknown, available, unsupported, noEnglishVoice }

enum StudentTtsActionResult { started, stopped, unavailable, failed }

@immutable
class StudentTtsPassageSegment {
  const StudentTtsPassageSegment({
    required this.sentenceIndex,
    required this.text,
  });

  final int sentenceIndex;
  final String text;
}

@immutable
class StudentTtsState {
  const StudentTtsState({
    required this.availability,
    required this.isInitializing,
    required this.isSpeaking,
    required this.activeTarget,
    required this.activeReadingId,
    required this.activeSentenceIndex,
    required this.activeWordId,
    required this.errorMessage,
  });

  const StudentTtsState.initial()
      : availability = StudentTtsAvailability.unknown,
        isInitializing = false,
        isSpeaking = false,
        activeTarget = null,
        activeReadingId = null,
        activeSentenceIndex = null,
        activeWordId = null,
        errorMessage = null;

  final StudentTtsAvailability availability;
  final bool isInitializing;
  final bool isSpeaking;
  final StudentTtsTarget? activeTarget;
  final String? activeReadingId;
  final int? activeSentenceIndex;
  final String? activeWordId;
  final String? errorMessage;

  bool get isUnavailable =>
      availability == StudentTtsAvailability.unsupported ||
      availability == StudentTtsAvailability.noEnglishVoice;

  StudentTtsState copyWith({
    StudentTtsAvailability? availability,
    bool? isInitializing,
    bool? isSpeaking,
    StudentTtsTarget? activeTarget,
    String? activeReadingId,
    int? activeSentenceIndex,
    String? activeWordId,
    String? errorMessage,
    bool clearTarget = false,
    bool clearError = false,
  }) {
    return StudentTtsState(
      availability: availability ?? this.availability,
      isInitializing: isInitializing ?? this.isInitializing,
      isSpeaking: isSpeaking ?? this.isSpeaking,
      activeTarget: clearTarget ? null : activeTarget ?? this.activeTarget,
      activeReadingId:
          clearTarget ? null : activeReadingId ?? this.activeReadingId,
      activeSentenceIndex:
          clearTarget ? null : activeSentenceIndex ?? this.activeSentenceIndex,
      activeWordId: clearTarget ? null : activeWordId ?? this.activeWordId,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

abstract interface class StudentTtsEngine {
  Future<StudentTtsAvailability> ensureInitialized();
  Future<void> speak(String text);
  Future<void> stop();
  Future<void> dispose();
}

class NativeStudentTtsEngine implements StudentTtsEngine {
  FlutterTts get _tts => _flutterTts ??= FlutterTts();

  FlutterTts? _flutterTts;
  bool _initialized = false;
  StudentTtsAvailability _availability = StudentTtsAvailability.unknown;

  @override
  Future<StudentTtsAvailability> ensureInitialized() async {
    if (_initialized) {
      return _availability;
    }

    _initialized = true;
    try {
      await _tts.awaitSpeakCompletion(true);
      final configured = kIsWeb
          ? await _configureEnglishLanguage()
          : await _configureNativeEnglishVoice();
      _availability = configured
          ? StudentTtsAvailability.available
          : StudentTtsAvailability.noEnglishVoice;
    } catch (_) {
      _availability = StudentTtsAvailability.unsupported;
    }

    return _availability;
  }

  @override
  Future<void> speak(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }

    await _tts.speak(trimmed);
  }

  @override
  Future<void> stop() async {
    final tts = _flutterTts;
    if (tts == null) {
      return;
    }

    try {
      await tts.stop();
    } catch (_) {
      // Swallow stop failures; playback commands will surface their own errors.
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
  }

  Future<bool> _configureNativeEnglishVoice() async {
    try {
      final voices = await _tts.getVoices;
      final parsedVoices = _parseVoices(voices);
      for (final voice in parsedVoices) {
        if (!voice.locale.toLowerCase().startsWith('en')) {
          continue;
        }
        await _tts.setLanguage(voice.locale);
        await _tts.setVoice(voice.rawVoice);
        return true;
      }
    } catch (_) {
      // Fall through to language-based detection.
    }

    return _configureEnglishLanguage();
  }

  Future<bool> _configureEnglishLanguage() async {
    for (final language in const <String>['en-US', 'en-GB']) {
      if (await _trySetLanguage(language)) {
        return true;
      }
    }

    try {
      final languages = await _tts.getLanguages;
      if (languages is Iterable) {
        for (final candidate in languages) {
          final language = candidate?.toString() ?? '';
          if (!language.toLowerCase().startsWith('en')) {
            continue;
          }
          if (await _trySetLanguage(language)) {
            return true;
          }
        }
      }
    } catch (_) {
      // Language probing is best effort.
    }

    return false;
  }

  Future<bool> _trySetLanguage(String language) async {
    try {
      final available = await _tts.isLanguageAvailable(language);
      if (!_isTruthyResult(available)) {
        return false;
      }
      final result = await _tts.setLanguage(language);
      return _isTruthyResult(result, allowNull: true);
    } catch (_) {
      return false;
    }
  }

  bool _isTruthyResult(dynamic result, {bool allowNull = false}) {
    if (result == null) {
      return allowNull;
    }
    if (result is bool) {
      return result;
    }
    if (result is num) {
      return result != 0;
    }
    if (result is String) {
      final normalized = result.trim().toLowerCase();
      return normalized == '1' ||
          normalized == 'true' ||
          normalized == 'success' ||
          normalized == 'ok';
    }
    return true;
  }

  List<_NativeTtsVoice> _parseVoices(dynamic voices) {
    if (voices is! Iterable) {
      return const <_NativeTtsVoice>[];
    }

    return voices
        .whereType<Map<dynamic, dynamic>>()
        .map((voice) {
          final normalized = <String, String>{};
          for (final entry in voice.entries) {
            final key = entry.key?.toString();
            final value = entry.value?.toString();
            if (key == null || value == null || value.isEmpty) {
              continue;
            }
            normalized[key] = value;
          }

          final locale = normalized['locale'] ??
              normalized['language'] ??
              normalized['identifier'] ??
              '';
          return _NativeTtsVoice(locale: locale, rawVoice: normalized);
        })
        .where((voice) => voice.locale.isNotEmpty && voice.rawVoice.isNotEmpty)
        .toList(growable: false);
  }
}

class _NativeTtsVoice {
  const _NativeTtsVoice({required this.locale, required this.rawVoice});

  final String locale;
  final Map<String, String> rawVoice;
}
