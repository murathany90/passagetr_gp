import '../../models/content_models.dart';
import '../../repositories/static_dictionary_repository.dart';

/// Canonical reading display title used everywhere:
/// `001 - English Title (Türkçe Başlık)`.
String readingDisplayTitle({
  required String? sourceNumber,
  required String displayTitle,
  String? turkishTitle,
}) {
  final number = (sourceNumber ?? '').trim();
  final english = displayTitle.trim();
  final turkish = (turkishTitle ?? '').trim();
  final head = number.isEmpty ? english : '$number - $english';
  return turkish.isEmpty ? head : '$head ($turkish)';
}

/// Canonical display title for a [ReadingPassage] record.
String readingPassageDisplayTitle(ReadingPassage passage) =>
    readingDisplayTitle(
      sourceNumber: passage.sourceNumber,
      displayTitle: (passage.displayTitle ?? passage.title).trim().isEmpty
          ? passage.title
          : (passage.displayTitle ?? passage.title),
      turkishTitle: passage.turkishTitle,
    );

class ReadingArticleSection {
  const ReadingArticleSection({
    required this.lookupIndex,
    required this.englishText,
    this.turkishText,
  });

  final int lookupIndex;
  final String englishText;
  final String? turkishText;
}

class SentenceToken {
  const SentenceToken({required this.displayWord, required this.lookupQuery});

  final String displayWord;
  final String lookupQuery;
  bool get isLookupable => lookupQuery.isNotEmpty;
}

final RegExp _tokenPattern = RegExp(r'\S+');

List<ReadingArticleSection> resolveArticleSections(
    List<ReadingSentence> sentences) {
  return sentences
      .where((sentence) => sentence.englishText.trim().isNotEmpty)
      .map((sentence) => ReadingArticleSection(
            lookupIndex: sentence.index,
            englishText: sentence.englishText,
            turkishText: sentence.turkishText,
          ))
      .toList(growable: false);
}

List<SentenceToken> tokenizeSentence(String text) =>
    _tokenPattern.allMatches(text).map((match) {
      final display = match.group(0) ?? '';
      return SentenceToken(
          displayWord: display, lookupQuery: normalizeDictionaryQuery(display));
    }).toList(growable: false);

String normalizeDictionaryQuery(String value) =>
    normalizeDictionaryLookup(value);
