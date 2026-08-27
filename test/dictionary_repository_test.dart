import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passagetr_gp/repositories/static_content_repository.dart';
import 'package:passagetr_gp/repositories/static_dictionary_repository.dart';
import 'package:passagetr_gp/repositories/word_lookup_service.dart';

void main() {
  test('dictionary findAll normalizes a query and lazily loads one shard',
      () async {
    final bundle = _RecordingFileAssetBundle();
    final repository = StaticDictionaryRepository(bundle: bundle);

    final entries = await repository.findAll('  “access” ');
    final suggestions = await repository.suggest('ac');

    expect(entries, hasLength(2));
    expect(entries.map((entry) => entry.enWord.toLowerCase()),
        everyElement('access'));
    expect(entries.map((entry) => entry.trMeaning).toSet(), hasLength(2));
    expect(suggestions, isNotEmpty);
    expect(suggestions.first.normalizedKey, startsWith('ac'));
    final dictionaryLoads = bundle.loaded
        .where((path) => path.contains('/dictionary/'))
        .toList(growable: false);
    expect(dictionaryLoads, hasLength(2));
    expect(dictionaryLoads, contains(endsWith('/dictionary/index.json')));
  });

  test('main 5,314-word content wins before dictionary lookup', () async {
    final content = StaticContentRepository(bundle: _FileAssetBundle());
    final dictionary = StaticDictionaryRepository(bundle: _FileAssetBundle());
    final target = (await content.loadWords()).first;
    final service = WordLookupService(content: content, dictionary: dictionary);

    final result = await service.find(target.enWord);

    expect(result.word?.id, target.id);
    expect(result.dictionaryEntry, isNull);
  });
}

class _FileAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bytes = await File(key).readAsBytes();
    return ByteData.sublistView(bytes);
  }
}

class _RecordingFileAssetBundle extends _FileAssetBundle {
  final List<String> loaded = <String>[];

  @override
  Future<ByteData> load(String key) {
    loaded.add(key);
    return super.load(key);
  }
}
