import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../models/content_models.dart';
import 'static_content_repository.dart';

const _smartApostrophes = <String, String>{
  '\u2018': "'",
  '\u2019': "'",
  '\u02bc': "'",
};
const _hyphens = <String, String>{
  '\u2010': '-',
  '\u2011': '-',
  '\u2012': '-',
  '\u2013': '-',
  '\u2014': '-',
  '\u2212': '-',
};
final _edgePunctuation = RegExp(r'^[^A-Za-z0-9]+|[^A-Za-z0-9]+$');
final _whitespace = RegExp(r'\s+');

String normalizeDictionaryLookup(String value) {
  var result = value.trim().toLowerCase();
  for (final entry in _smartApostrophes.entries) {
    result = result.replaceAll(entry.key, entry.value);
  }
  for (final entry in _hyphens.entries) {
    result = result.replaceAll(entry.key, entry.value);
  }
  result = result.replaceAll(_whitespace, ' ');
  return result.replaceAll(_edgePunctuation, '').trim();
}

class StaticDictionaryRepository {
  StaticDictionaryRepository({
    AssetBundle? bundle,
    this.root = 'assets/content/v1',
  }) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  final String root;
  Future<_DictionaryIndex>? _indexFuture;
  final Map<String, Future<List<DictionaryEntry>>> _shardCache =
      <String, Future<List<DictionaryEntry>>>{};

  Future<DictionaryEntry?> find(String query) async {
    final normalized = normalizeDictionaryLookup(query);
    if (normalized.isEmpty) {
      return null;
    }
    final index = await _index();
    final shard = index.shards.where((candidate) {
      return normalized.compareTo(candidate.rangeStart) >= 0 &&
          normalized.compareTo(candidate.rangeEnd) <= 0;
    }).firstOrNull;
    if (shard == null) {
      return null;
    }
    final entries = await _loadShard(shard);
    return entries
        .where((entry) => entry.normalizedKey == normalized)
        .firstOrNull;
  }

  Future<_DictionaryIndex> _index() => _indexFuture ??= _loadIndex();

  Future<_DictionaryIndex> _loadIndex() async {
    final json = await _loadJson('dictionary/index.json');
    final shards = ((json['shards'] as List<Object?>?) ?? const <Object?>[])
        .map((item) => DictionaryShard.fromJson(_jsonMap(item)))
        .toList(growable: false);
    if (json['contentVersion'] != 'v1' || shards.isEmpty) {
      throw const StaticContentException('Sözlük indeksi eksik veya bozuk.');
    }
    return _DictionaryIndex(List<DictionaryShard>.unmodifiable(shards));
  }

  Future<List<DictionaryEntry>> _loadShard(DictionaryShard shard) {
    return _shardCache.putIfAbsent(shard.file, () async {
      final json = await _loadJson(shard.file);
      final entries = ((json['records'] as List<Object?>?) ?? const <Object?>[])
          .map((item) => DictionaryEntry.fromJson(_jsonMap(item)))
          .toList(growable: false);
      if (entries.length != shard.recordCount ||
          entries.any(
              (entry) => entry.enWord.isEmpty || entry.trMeaning.isEmpty)) {
        throw StaticContentException('Sözlük parçası geçersiz: ${shard.file}');
      }
      return List<DictionaryEntry>.unmodifiable(entries);
    });
  }

  Future<Map<String, Object?>> _loadJson(String relativePath) async {
    try {
      final raw = await _bundle.loadString('$root/$relativePath');
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('JSON object bekleniyordu.');
      }
      return Map<String, Object?>.from(decoded);
    } catch (error) {
      if (error is StaticContentException) rethrow;
      throw StaticContentException('Asset yüklenemedi: $relativePath', error);
    }
  }
}

class _DictionaryIndex {
  const _DictionaryIndex(this.shards);

  final List<DictionaryShard> shards;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

Map<String, Object?> _jsonMap(Object? value) =>
    Map<String, Object?>.from(value! as Map);
