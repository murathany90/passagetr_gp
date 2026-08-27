import 'package:shared_preferences/shared_preferences.dart';

class LocalProgressSnapshot {
  const LocalProgressSnapshot({
    required this.isLoaded,
    this.favoriteWordIds = const <String>{},
    this.knownWordIds = const <String>{},
    this.completedReadingIds = const <String>{},
    this.wordPackId,
    this.wordLevel,
    this.readingLevel,
    this.readingCategory,
  });

  const LocalProgressSnapshot.empty() : this(isLoaded: false);

  final bool isLoaded;
  final Set<String> favoriteWordIds;
  final Set<String> knownWordIds;
  final Set<String> completedReadingIds;
  final String? wordPackId;
  final String? wordLevel;
  final String? readingLevel;
  final String? readingCategory;

  LocalProgressSnapshot copyWith({
    bool? isLoaded,
    Set<String>? favoriteWordIds,
    Set<String>? knownWordIds,
    Set<String>? completedReadingIds,
    String? wordPackId,
    bool clearWordPackId = false,
    String? wordLevel,
    bool clearWordLevel = false,
    String? readingLevel,
    bool clearReadingLevel = false,
    String? readingCategory,
    bool clearReadingCategory = false,
  }) =>
      LocalProgressSnapshot(
        isLoaded: isLoaded ?? this.isLoaded,
        favoriteWordIds: favoriteWordIds ?? this.favoriteWordIds,
        knownWordIds: knownWordIds ?? this.knownWordIds,
        completedReadingIds: completedReadingIds ?? this.completedReadingIds,
        wordPackId: clearWordPackId ? null : wordPackId ?? this.wordPackId,
        wordLevel: clearWordLevel ? null : wordLevel ?? this.wordLevel,
        readingLevel:
            clearReadingLevel ? null : readingLevel ?? this.readingLevel,
        readingCategory: clearReadingCategory
            ? null
            : readingCategory ?? this.readingCategory,
      );
}

class LocalProgressRepository {
  static const _favoritesKey = 'passagetr.favoriteWordIds.v1';
  static const _knownKey = 'passagetr.knownWordIds.v1';
  static const _completedReadingsKey = 'passagetr.completedReadingIds.v1';
  static const _wordPackKey = 'passagetr.wordPackId.v1';
  static const _wordLevelKey = 'passagetr.wordLevel.v1';
  static const _readingLevelKey = 'passagetr.readingLevel.v1';
  static const _readingCategoryKey = 'passagetr.readingCategory.v1';

  Future<SharedPreferences>? _preferencesFuture;

  Future<LocalProgressSnapshot> load() async {
    final preferences = await _preferences();
    return LocalProgressSnapshot(
      isLoaded: true,
      favoriteWordIds: _readSet(preferences, _favoritesKey),
      knownWordIds: _readSet(preferences, _knownKey),
      completedReadingIds: _readSet(preferences, _completedReadingsKey),
      wordPackId: preferences.getString(_wordPackKey),
      wordLevel: preferences.getString(_wordLevelKey),
      readingLevel: preferences.getString(_readingLevelKey),
      readingCategory: preferences.getString(_readingCategoryKey),
    );
  }

  Future<void> saveFavoriteWordIds(Set<String> ids) =>
      _saveSet(_favoritesKey, ids);

  Future<void> saveKnownWordIds(Set<String> ids) => _saveSet(_knownKey, ids);

  Future<void> saveCompletedReadingIds(Set<String> ids) =>
      _saveSet(_completedReadingsKey, ids);

  Future<void> saveWordFilters({String? packId, String? level}) async {
    final preferences = await _preferences();
    await _saveOptional(preferences, _wordPackKey, packId);
    await _saveOptional(preferences, _wordLevelKey, level);
  }

  Future<void> saveReadingFilters({String? level, String? category}) async {
    final preferences = await _preferences();
    await _saveOptional(preferences, _readingLevelKey, level);
    await _saveOptional(preferences, _readingCategoryKey, category);
  }

  Future<SharedPreferences> _preferences() =>
      _preferencesFuture ??= SharedPreferences.getInstance();

  Set<String> _readSet(SharedPreferences preferences, String key) =>
      Set<String>.unmodifiable(
          preferences.getStringList(key) ?? const <String>[]);

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
