import '../../models/content_models.dart';

/// The canonical taxonomy is carried unchanged from each word's `tags_raw`.
const practiceItemCountOptions = <int>[20, 40, 80, 100, 200];
const matchingRoundSize = 10;

/// Converts the pre-migration local preference to the current CSV taxonomy.
String? migrateLegacyWordTag(String? tag) =>
    tag?.contains('_') ?? false ? tag!.replaceAll('_', ' & ') : tag;

List<String> canonicalWordTags(Iterable<WordEntry> words) {
  final tags = <String>{
    for (final word in words) ...word.tags.where((tag) => tag.isNotEmpty),
  }.toList()
    ..sort();
  return tags;
}

List<String> canonicalWordLevels(Iterable<WordEntry> words) {
  final levels = words
      .map((word) => word.level)
      .whereType<String>()
      .where((level) => level.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  return levels;
}

bool matchesWordFilters(
  WordEntry word, {
  String? level,
  String? tag,
}) =>
    (level == null || word.level == level) &&
    (tag == null || word.tags.contains(tag));

List<WordEntry> wordsForFilters(
  Iterable<WordEntry> words, {
  String? level,
  String? tag,
}) =>
    words
        .where((word) => matchesWordFilters(word, level: level, tag: tag))
        .toList(growable: false);

List<List<T>> splitWordPracticeRounds<T>(
  List<T> items, {
  int roundSize = matchingRoundSize,
}) {
  if (roundSize <= 0) {
    throw ArgumentError.value(roundSize, 'roundSize', 'Pozitif olmalı.');
  }
  return <List<T>>[
    for (var start = 0; start < items.length; start += roundSize)
      items.sublist(start, (start + roundSize).clamp(0, items.length)),
  ];
}
