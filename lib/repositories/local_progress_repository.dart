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
    this.completedStudySectionKeys = const <String>{},
    this.studyLastModuleId,
    this.studyLastSection,
    this.studyQuestionAnswers = const <String, String>{},
    this.studyQuestionCorrectness = const <String, bool>{},
    this.studyQuestionContentVersion,
    this.studyQuestionFingerprints = const <String, String>{},
    this.testLastModuleNo,
    this.testFavoriteWordIds = const <String>{},
    this.testFlashcardKnownIds = const <String>{},
    this.completedTestMatchingModuleIds = const <String>{},
    this.testMatchingBestScores = const <String, int>{},
    this.testQuickTestBestScores = const <String, int>{},
    this.testKnownStructureIds = const <String>{},
    this.testQuestionAnswers = const <String, String>{},
    this.testQuestionCorrectness = const <String, bool>{},
    this.testQuestionContentVersion,
    this.testQuestionFingerprints = const <String, String>{},
    this.testExamLastQuestionIndexes = const <String, int>{},
    this.testExamBestScores = const <String, int>{},
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
  final Set<String> completedStudySectionKeys;
  final String? studyLastModuleId;
  final String? studyLastSection;
  final Map<String, String> studyQuestionAnswers;
  final Map<String, bool> studyQuestionCorrectness;
  final String? studyQuestionContentVersion;
  final Map<String, String> studyQuestionFingerprints;
  final int? testLastModuleNo;
  final Set<String> testFavoriteWordIds;
  final Set<String> testFlashcardKnownIds;
  final Set<String> completedTestMatchingModuleIds;
  final Map<String, int> testMatchingBestScores;
  final Map<String, int> testQuickTestBestScores;
  final Set<String> testKnownStructureIds;
  final Map<String, String> testQuestionAnswers;
  final Map<String, bool> testQuestionCorrectness;
  final String? testQuestionContentVersion;
  final Map<String, String> testQuestionFingerprints;
  final Map<String, int> testExamLastQuestionIndexes;
  final Map<String, int> testExamBestScores;

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
    Set<String>? completedStudySectionKeys,
    String? studyLastModuleId,
    bool clearStudyLastModuleId = false,
    String? studyLastSection,
    bool clearStudyLastSection = false,
    Map<String, String>? studyQuestionAnswers,
    Map<String, bool>? studyQuestionCorrectness,
    String? studyQuestionContentVersion,
    bool clearStudyQuestionContentVersion = false,
    Map<String, String>? studyQuestionFingerprints,
    int? testLastModuleNo,
    bool clearTestLastModuleNo = false,
    Set<String>? testFavoriteWordIds,
    Set<String>? testFlashcardKnownIds,
    Set<String>? completedTestMatchingModuleIds,
    Map<String, int>? testMatchingBestScores,
    Map<String, int>? testQuickTestBestScores,
    Set<String>? testKnownStructureIds,
    Map<String, String>? testQuestionAnswers,
    Map<String, bool>? testQuestionCorrectness,
    String? testQuestionContentVersion,
    bool clearTestQuestionContentVersion = false,
    Map<String, String>? testQuestionFingerprints,
    Map<String, int>? testExamLastQuestionIndexes,
    Map<String, int>? testExamBestScores,
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
        completedStudySectionKeys:
            completedStudySectionKeys ?? this.completedStudySectionKeys,
        studyLastModuleId: clearStudyLastModuleId
            ? null
            : studyLastModuleId ?? this.studyLastModuleId,
        studyLastSection: clearStudyLastSection
            ? null
            : studyLastSection ?? this.studyLastSection,
        studyQuestionAnswers: studyQuestionAnswers ?? this.studyQuestionAnswers,
        studyQuestionCorrectness:
            studyQuestionCorrectness ?? this.studyQuestionCorrectness,
        studyQuestionContentVersion: clearStudyQuestionContentVersion
            ? null
            : studyQuestionContentVersion ?? this.studyQuestionContentVersion,
        studyQuestionFingerprints:
            studyQuestionFingerprints ?? this.studyQuestionFingerprints,
        testLastModuleNo: clearTestLastModuleNo
            ? null
            : testLastModuleNo ?? this.testLastModuleNo,
        testFavoriteWordIds: testFavoriteWordIds ?? this.testFavoriteWordIds,
        testFlashcardKnownIds:
            testFlashcardKnownIds ?? this.testFlashcardKnownIds,
        completedTestMatchingModuleIds: completedTestMatchingModuleIds ??
            this.completedTestMatchingModuleIds,
        testMatchingBestScores:
            testMatchingBestScores ?? this.testMatchingBestScores,
        testQuickTestBestScores:
            testQuickTestBestScores ?? this.testQuickTestBestScores,
        testKnownStructureIds:
            testKnownStructureIds ?? this.testKnownStructureIds,
        testQuestionAnswers: testQuestionAnswers ?? this.testQuestionAnswers,
        testQuestionCorrectness:
            testQuestionCorrectness ?? this.testQuestionCorrectness,
        testQuestionContentVersion: clearTestQuestionContentVersion
            ? null
            : testQuestionContentVersion ?? this.testQuestionContentVersion,
        testQuestionFingerprints:
            testQuestionFingerprints ?? this.testQuestionFingerprints,
        testExamLastQuestionIndexes:
            testExamLastQuestionIndexes ?? this.testExamLastQuestionIndexes,
        testExamBestScores: testExamBestScores ?? this.testExamBestScores,
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
  static const _completedStudySectionsKey =
      'passagetr.completedStudySectionKeys.v1';
  static const _studyLastModuleKey = 'passagetr.studyLastModuleId.v1';
  static const _studyLastSectionKey = 'passagetr.studyLastSection.v1';
  static const _studyQuestionAnswersKey = 'passagetr.studyQuestionAnswers.v1';
  static const _studyQuestionCorrectnessKey =
      'passagetr.studyQuestionCorrectness.v1';
  static const _studyQuestionContentVersionKey =
      'passagetr.studyQuestionContentVersion.v1';
  static const _studyQuestionFingerprintsKey =
      'passagetr.studyQuestionFingerprints.v1';
  static const _testLastModuleKey = 'passagetr.testLastModuleNo.v1';
  static const _testFavoriteWordsKey = 'passagetr.testFavoriteWordIds.v1';
  static const _testFlashcardKnownKey = 'passagetr.testFlashcardKnownIds.v1';
  static const _completedTestMatchingKey =
      'passagetr.completedTestMatchingModuleIds.v1';
  static const _testMatchingBestScoresKey =
      'passagetr.testMatchingBestScores.v1';
  static const _testQuickTestBestScoresKey =
      'passagetr.testQuickTestBestScores.v1';
  static const _testKnownStructureIdsKey = 'passagetr.testKnownStructureIds.v1';
  static const _testQuestionAnswersKey = 'passagetr.testQuestionAnswers.v1';
  static const _testQuestionCorrectnessKey =
      'passagetr.testQuestionCorrectness.v1';
  static const _testQuestionContentVersionKey =
      'passagetr.testQuestionContentVersion.v1';
  static const _testQuestionFingerprintsKey =
      'passagetr.testQuestionFingerprints.v1';
  static const _testExamLastQuestionIndexesKey =
      'passagetr.testExamLastQuestionIndexes.v1';
  static const _testExamBestScoresKey = 'passagetr.testExamBestScores.v1';

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
      completedStudySectionKeys:
          _readSet(preferences, _completedStudySectionsKey),
      studyLastModuleId: preferences.getString(_studyLastModuleKey),
      studyLastSection: preferences.getString(_studyLastSectionKey),
      studyQuestionAnswers: _readMap(preferences, _studyQuestionAnswersKey),
      studyQuestionCorrectness:
          _readBoolMap(preferences, _studyQuestionCorrectnessKey),
      studyQuestionContentVersion:
          preferences.getString(_studyQuestionContentVersionKey),
      studyQuestionFingerprints:
          _readMap(preferences, _studyQuestionFingerprintsKey),
      testLastModuleNo: preferences.getInt(_testLastModuleKey),
      testFavoriteWordIds: _readSet(preferences, _testFavoriteWordsKey),
      testFlashcardKnownIds: _readSet(preferences, _testFlashcardKnownKey),
      completedTestMatchingModuleIds:
          _readSet(preferences, _completedTestMatchingKey),
      testMatchingBestScores:
          _readIntMap(preferences, _testMatchingBestScoresKey),
      testQuickTestBestScores:
          _readIntMap(preferences, _testQuickTestBestScoresKey),
      testKnownStructureIds: _readSet(preferences, _testKnownStructureIdsKey),
      testQuestionAnswers: _readMap(preferences, _testQuestionAnswersKey),
      testQuestionCorrectness:
          _readBoolMap(preferences, _testQuestionCorrectnessKey),
      testQuestionContentVersion:
          preferences.getString(_testQuestionContentVersionKey),
      testQuestionFingerprints:
          _readMap(preferences, _testQuestionFingerprintsKey),
      testExamLastQuestionIndexes:
          _readIntMap(preferences, _testExamLastQuestionIndexesKey),
      testExamBestScores: _readIntMap(preferences, _testExamBestScoresKey),
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

  Future<void> saveCompletedStudySectionKeys(Set<String> keys) =>
      _saveSet(_completedStudySectionsKey, keys);

  Future<void> saveStudyLocation({String? moduleId, String? section}) async {
    final preferences = await _preferences();
    await _saveOptional(preferences, _studyLastModuleKey, moduleId);
    await _saveOptional(preferences, _studyLastSectionKey, section);
  }

  Future<void> saveStudyQuestionAnswers(Map<String, String> answers) async {
    final preferences = await _preferences();
    await preferences.setString(_studyQuestionAnswersKey, jsonEncode(answers));
  }

  Future<void> saveStudyQuestionCorrectness(
      Map<String, bool> correctness) async {
    final preferences = await _preferences();
    await preferences.setString(
      _studyQuestionCorrectnessKey,
      jsonEncode(correctness),
    );
  }

  Future<void> saveStudyQuestionContent({
    required String version,
    required Map<String, String> fingerprints,
  }) async {
    final preferences = await _preferences();
    await _saveOptional(preferences, _studyQuestionContentVersionKey, version);
    await preferences.setString(
      _studyQuestionFingerprintsKey,
      jsonEncode(fingerprints),
    );
  }

  Future<void> saveTestLastModuleNo(int? moduleNo) async {
    final preferences = await _preferences();
    if (moduleNo == null) {
      await preferences.remove(_testLastModuleKey);
    } else {
      await preferences.setInt(_testLastModuleKey, moduleNo);
    }
  }

  Future<void> saveTestFavoriteWordIds(Set<String> ids) =>
      _saveSet(_testFavoriteWordsKey, ids);

  Future<void> saveTestFlashcardKnownIds(Set<String> ids) =>
      _saveSet(_testFlashcardKnownKey, ids);

  Future<void> saveCompletedTestMatchingModuleIds(Set<String> ids) =>
      _saveSet(_completedTestMatchingKey, ids);

  Future<void> saveTestMatchingBestScores(Map<String, int> scores) =>
      _saveIntMap(_testMatchingBestScoresKey, scores);

  Future<void> saveTestQuickTestBestScores(Map<String, int> scores) =>
      _saveIntMap(_testQuickTestBestScoresKey, scores);

  Future<void> saveTestKnownStructureIds(Set<String> ids) =>
      _saveSet(_testKnownStructureIdsKey, ids);

  Future<void> saveTestQuestionAnswers(Map<String, String> answers) async {
    final preferences = await _preferences();
    await preferences.setString(_testQuestionAnswersKey, jsonEncode(answers));
  }

  Future<void> saveTestQuestionCorrectness(
      Map<String, bool> correctness) async {
    final preferences = await _preferences();
    await preferences.setString(
      _testQuestionCorrectnessKey,
      jsonEncode(correctness),
    );
  }

  Future<void> saveTestQuestionContent({
    required String version,
    required Map<String, String> fingerprints,
  }) async {
    final preferences = await _preferences();
    await _saveOptional(preferences, _testQuestionContentVersionKey, version);
    await preferences.setString(
      _testQuestionFingerprintsKey,
      jsonEncode(fingerprints),
    );
  }

  Future<void> saveTestExamLastQuestionIndexes(Map<String, int> indexes) =>
      _saveIntMap(_testExamLastQuestionIndexesKey, indexes);

  Future<void> saveTestExamBestScores(Map<String, int> scores) =>
      _saveIntMap(_testExamBestScoresKey, scores);

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

  Map<String, bool> _readBoolMap(SharedPreferences preferences, String key) {
    final raw = preferences.getString(key);
    if (raw == null || raw.isEmpty) return const <String, bool>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <String, bool>{};
      return Map<String, bool>.unmodifiable(decoded.map(
        (key, value) => MapEntry(key.toString(), value == true),
      ));
    } catch (_) {
      return const <String, bool>{};
    }
  }

  Map<String, int> _readIntMap(SharedPreferences preferences, String key) {
    final raw = preferences.getString(key);
    if (raw == null || raw.isEmpty) return const <String, int>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <String, int>{};
      return Map<String, int>.unmodifiable(decoded.map(
        (key, value) => MapEntry(key.toString(), value is int ? value : 0),
      ));
    } catch (_) {
      return const <String, int>{};
    }
  }

  Future<void> _saveSet(String key, Set<String> ids) async {
    final preferences = await _preferences();
    await preferences.setStringList(key, ids.toList()..sort());
  }

  Future<void> _saveIntMap(String key, Map<String, int> values) async {
    final preferences = await _preferences();
    await preferences.setString(key, jsonEncode(values));
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
