import '../../models/content_models.dart';

/// The canonical taxonomy is carried unchanged from each word's `tags_raw`.
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
