import '../models/content_models.dart';
import 'static_content_repository.dart';
import 'static_dictionary_repository.dart';

class WordLookupResult {
  const WordLookupResult._({this.word, this.dictionaryEntries = const []});

  const WordLookupResult.word(WordEntry value) : this._(word: value);

  const WordLookupResult.dictionary(List<DictionaryEntry> values)
      : this._(dictionaryEntries: values);

  const WordLookupResult.notFound() : this._();

  final WordEntry? word;
  final List<DictionaryEntry> dictionaryEntries;
  DictionaryEntry? get dictionaryEntry => dictionaryEntries.firstOrNull;
  bool get isFound => word != null || dictionaryEntries.isNotEmpty;
}

class WordLookupService {
  WordLookupService({
    required StaticContentRepository content,
    required StaticDictionaryRepository dictionary,
  })  : _content = content,
        _dictionary = dictionary;

  final StaticContentRepository _content;
  final StaticDictionaryRepository _dictionary;
  Map<String, WordEntry>? _wordIndex;
  int _indexedWordCount = -1;

  Future<WordLookupResult> find(String query) async {
    final normalized = normalizeDictionaryLookup(query);
    if (normalized.isEmpty) {
      return const WordLookupResult.notFound();
    }
    final words = await _content.loadWords();
    if (_wordIndex == null || _indexedWordCount != words.length) {
      final index = <String, WordEntry>{};
      for (final entry in words) {
        index.putIfAbsent(
            normalizeDictionaryLookup(entry.enWord), () => entry);
      }
      _wordIndex = index;
      _indexedWordCount = words.length;
    }
    final word = _wordIndex![normalized];
    if (word != null) {
      return WordLookupResult.word(word);
    }
    final entries = await _dictionary.findAll(normalized);
    return entries.isEmpty
        ? const WordLookupResult.notFound()
        : WordLookupResult.dictionary(entries);
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
