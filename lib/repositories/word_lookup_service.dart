import '../models/content_models.dart';
import 'static_content_repository.dart';
import 'static_dictionary_repository.dart';

class WordLookupResult {
  const WordLookupResult._({this.word, this.dictionaryEntry});

  const WordLookupResult.word(WordEntry value) : this._(word: value);

  const WordLookupResult.dictionary(DictionaryEntry value)
      : this._(dictionaryEntry: value);

  const WordLookupResult.notFound() : this._();

  final WordEntry? word;
  final DictionaryEntry? dictionaryEntry;
  bool get isFound => word != null || dictionaryEntry != null;
}

class WordLookupService {
  const WordLookupService({
    required StaticContentRepository content,
    required StaticDictionaryRepository dictionary,
  })  : _content = content,
        _dictionary = dictionary;

  final StaticContentRepository _content;
  final StaticDictionaryRepository _dictionary;

  Future<WordLookupResult> find(String query) async {
    final normalized = normalizeDictionaryLookup(query);
    if (normalized.isEmpty) {
      return const WordLookupResult.notFound();
    }
    final words = await _content.loadWords();
    final word = words
        .where((entry) => normalizeDictionaryLookup(entry.enWord) == normalized)
        .firstOrNull;
    if (word != null) {
      return WordLookupResult.word(word);
    }
    final entry = await _dictionary.find(normalized);
    return entry == null
        ? const WordLookupResult.notFound()
        : WordLookupResult.dictionary(entry);
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
