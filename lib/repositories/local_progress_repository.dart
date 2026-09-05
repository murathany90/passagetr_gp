import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalProgressSnapshot {
  const LocalProgressSnapshot({
    required this.isLoaded,
    this.favoriteWordIds = const <String>{},
    this.knownWordIds = const <String>{},
    this.completedReadingIds = const <String>{},
    this.wordTag,
    this.wordLevel,
    this.readingLevel,
    this.readingCategory,
    this.completedStudyModuleIds = const <String>{},
    this.studyLastModuleId,
    this.studyLastSection,
    this.studyQuestionAnswers = const <String, String>{},
  });

  const LocalProgressSnapshot.empty() : this(isLoaded: false);

  final bool isLoaded;
  final Set<String> favoriteWordIds;
  final Set<String> knownWordIds;
  final Set<String> completedReadingIds;
  final String? wordTag;
  final String? wordLevel;
  final String? readingLevel;
  final String? readingCategory;
  final Set<String> completedStudyModuleIds;
  final String? studyLastModuleId;
  final String? studyLastSection;
  final Map<String, String> studyQuestionAnswers;

  LocalProgressSnapshot copyWith({
    bool? isLoaded,
    Set<String>? favoriteWordIds,
    Set<String>? knownWordIds,
    Set<String>? completedReadingIds,
    String? wordTag,
    bool clearWordTag = false,
    String? wordLevel,
    bool clearWordLevel = false,
    String? readingLevel,
    bool clearReadingLevel = false,
    String? readingCategory,
    bool clearReadingCategory = false,
    Set<String>? completedStudyModuleIds,
    String? studyLastModuleId,
    bool clearStudyLastModuleId = false,
    String? studyLastSection,
    bool clearStudyLastSection = false,
    Map<String, String>? studyQuestionAnswers,
  }) =>
      LocalProgressSnapshot(
        isLoaded: isLoaded ?? this.isLoaded,
        favoriteWordIds: favoriteWordIds ?? this.favoriteWordIds,
        knownWordIds: knownWordIds ?? this.knownWordIds,
        completedReadingIds: completedReadingIds ?? this.completedReadingIds,
        wordTag: clearWordTag ? null : wordTag ?? this.wordTag,
        wordLevel: clearWordLevel ? null : wordLevel ?? this.wordLevel,
        readingLevel:
            clearReadingLevel ? null : readingLevel ?? this.readingLevel,
        readingCategory: clearReadingCategory
            ? null
            : readingCategory ?? this.readingCategory,
        completedStudyModuleIds:
            completedStudyModuleIds ?? this.completedStudyModuleIds,
        studyLastModuleId: clearStudyLastModuleId
            ? null
            : studyLastModuleId ?? this.studyLastModuleId,
        studyLastSection: clearStudyLastSection
            ? null
            : studyLastSection ?? this.studyLastSection,
        studyQuestionAnswers: studyQuestionAnswers ?? this.studyQuestionAnswers,
      );
}

class LocalProgressRepository {
  static const _favoritesKey = 'passagetr.favoriteWordIds.v1';
  static const _knownKey = 'passagetr.knownWordIds.v1';
  static const _completedReadingsKey = 'passagetr.completedReadingIds.v1';
  static const _wordTagKey = 'passagetr.wordTag.v1';
  static const _wordLevelKey = 'passagetr.wordLevel.v1';
  static const _readingLevelKey = 'passagetr.readingLevel.v1';
  static const _readingCategoryKey = 'passagetr.readingCategory.v1';
  static const _completedStudyModulesKey =
      'passagetr.completedStudyModuleIds.v1';
  static const _studyLastModuleKey = 'passagetr.studyLastModuleId.v1';
  static const _studyLastSectionKey = 'passagetr.studyLastSection.v1';
  static const _studyQuestionAnswersKey = 'passagetr.studyQuestionAnswers.v1';

  Future<SharedPreferences>? _preferencesFuture;

  Future<LocalProgressSnapshot> load() async {
    final preferences = await _preferences();
    return LocalProgressSnapshot(
      isLoaded: true,
      favoriteWordIds: _readSet(preferences, _favoritesKey),
      knownWordIds: _readSet(preferences, _knownKey),
      completedReadingIds: _readSet(preferences, _completedReadingsKey),
      wordTag: preferences.getString(_wordTagKey),
      wordLevel: preferences.getString(_wordLevelKey),
      readingLevel: preferences.getString(_readingLevelKey),
      readingCategory: preferences.getString(_readingCategoryKey),
      completedStudyModuleIds: _readSet(preferences, _completedStudyModulesKey),
      studyLastModuleId: preferences.getString(_studyLastModuleKey),
      studyLastSection: preferences.getString(_studyLastSectionKey),
      studyQuestionAnswers: _readMap(preferences, _studyQuestionAnswersKey),
    );
  }

  Future<void> saveFavoriteWordIds(Set<String> ids) =>
      _saveSet(_favoritesKey, ids);

  Future<void> saveKnownWordIds(Set<String> ids) => _saveSet(_knownKey, ids);

  Future<void> saveCompletedReadingIds(Set<String> ids) =>
      _saveSet(_completedReadingsKey, ids);

  Future<void> saveWordFilters({String? tag, String? level}) async {
    final preferences = await _preferences();
    await _saveOptional(preferences, _wordTagKey, tag);
    await _saveOptional(preferences, _wordLevelKey, level);
  }

  Future<void> saveReadingFilters({String? level, String? category}) async {
    final preferences = await _preferences();
    await _saveOptional(preferences, _readingLevelKey, level);
    await _saveOptional(preferences, _readingCategoryKey, category);
  }

  Future<void> saveCompletedStudyModuleIds(Set<String> ids) =>
      _saveSet(_completedStudyModulesKey, ids);

  Future<void> saveStudyLocation({String? moduleId, String? section}) async {
    final preferences = await _preferences();
    await _saveOptional(preferences, _studyLastModuleKey, moduleId);
    await _saveOptional(preferences, _studyLastSectionKey, section);
  }

  Future<void> saveStudyQuestionAnswers(Map<String, String> answers) async {
    final preferences = await _preferences();
    await preferences.setString(_studyQuestionAnswersKey, jsonEncode(answers));
  }

  Future<SharedPreferences> _preferences() =>
      _preferencesFuture ??= SharedPreferences.getInstance();

  Set<String> _readSet(SharedPreferences preferences, String key) =>
      Set<String>.unmodifiable(
          preferences.getStringList(key) ?? const <String>[]);

  Map<String, String> _readMap(SharedPreferences preferences, String key) {
    final raw = preferences.getString(key);
    if (raw == null || raw.isEmpty) return const <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <String, String>{};
      return Map<String, String>.unmodifiable(decoded.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ));
    } catch (_) {
      return const <String, String>{};
    }
  }

  Future<void> _saveSet(String key, Set<String> ids) async {
    final preferences = await _preferences();
    await preferences.setStringList(key, ids.toList()..sort());
  }

  Future<void> _saveOptional(
    SharedPreferences preferences,
    String key,
    String? value,
  ) =>
      value == null || value.isEmpty
          ? preferences.remove(key)
          : preferences.setString(key, value);
}
