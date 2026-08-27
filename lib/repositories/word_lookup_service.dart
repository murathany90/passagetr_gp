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
    final entries = await _dictionary.findAll(normalized);
    return entries.isEmpty
        ? const WordLookupResult.notFound()
        : WordLookupResult.dictionary(entries);
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
