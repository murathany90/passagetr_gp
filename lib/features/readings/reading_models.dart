import '../../models/content_models.dart';

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
final RegExp _edgePunctuationPattern = RegExp(r'^[^A-Za-z0-9]+|[^A-Za-z0-9]+$');

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

String normalizeDictionaryQuery(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll('\u2019', "'")
    .replaceAll(_edgePunctuationPattern, '');
