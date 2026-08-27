import 'dart:convert';
import 'dart:math' as math;

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
    math.Random? random,
  })  : _bundle = bundle ?? rootBundle,
        _random = random ?? math.Random();

  final AssetBundle _bundle;
  final math.Random _random;
  final String root;
  Future<_DictionaryIndex>? _indexFuture;
  final Map<String, Future<List<DictionaryEntry>>> _shardCache =
      <String, Future<List<DictionaryEntry>>>{};

  Future<DictionaryEntry?> find(String query) async {
    final entries = await findAll(query);
    return entries.firstOrNull;
  }

  Future<List<DictionaryEntry>> findAll(String query) async {
    final normalized = normalizeDictionaryLookup(query);
    if (normalized.isEmpty) {
      return const <DictionaryEntry>[];
    }
    final index = await _index();
    final shard = index.shards.where((candidate) {
      return normalized.compareTo(candidate.rangeStart) >= 0 &&
          normalized.compareTo(candidate.rangeEnd) <= 0;
    }).firstOrNull;
    if (shard == null) {
      return const <DictionaryEntry>[];
    }
    final entries = await _loadShard(shard);
    final seenMeanings = <String>{};
    final matches = entries.where((entry) {
      if (entry.normalizedKey != normalized) {
        return false;
      }
      final dedupeKey = '${entry.pos?.trim().toLowerCase() ?? ''}\u241f'
          '${entry.trMeaning.trim().toLowerCase()}';
      return seenMeanings.add(dedupeKey);
    }).toList(growable: false);
    return List<DictionaryEntry>.unmodifiable(matches);
  }

  /// Samples unique headwords from a few weighted dictionary shards.
  ///
  /// `exclude` contains normalized headwords from the immediately previous
  /// selection. This keeps refreshes varied without building a full in-memory
  /// dictionary catalogue.
  Future<List<DictionaryEntry>> randomEntries({
    int count = 20,
    Iterable<String> exclude = const <String>[],
  }) async {
    if (count <= 0) return const <DictionaryEntry>[];
    final index = await _index();
    final seenHeadwords = <String>{
      for (final value in exclude)
        if (normalizeDictionaryLookup(value).isNotEmpty)
          normalizeDictionaryLookup(value),
    };
    final results = <DictionaryEntry>[];
    final remainingShards = List<DictionaryShard>.of(index.shards);
    final initialShardCount = math.min(
      remainingShards.length,
      math.max(1, (count + 7) ~/ 8),
    );

    while (results.length < count && remainingShards.isNotEmpty) {
      final requestedShards = results.isEmpty ? initialShardCount : 1;
      final selectedShards = <DictionaryShard>[
        for (var selected = 0;
            selected < requestedShards && remainingShards.isNotEmpty;
            selected++)
          _takeWeightedShard(remainingShards),
      ];
      final loadedShards = await Future.wait(selectedShards.map(_loadShard));
      for (final entries in loadedShards) {
        _sampleEntries(entries, count, seenHeadwords, results);
      }
    }
    return List<DictionaryEntry>.unmodifiable(results);
  }

  /// Returns one entry per matching headword without ever loading every shard.
  /// Two characters are enough to narrow the shard range in the bundled index.
  Future<List<DictionaryEntry>> suggest(String query, {int limit = 8}) async {
    final normalized = normalizeDictionaryLookup(query);
    if (normalized.length < 2 || limit <= 0) {
      return const <DictionaryEntry>[];
    }
    final index = await _index();
    final upperBound = '$normalized\uffff';
    final prefix = _dictionaryPrefix(normalized);
    final matchingShards = index.shards.where((shard) {
      return shard.prefix == prefix &&
          shard.rangeEnd.compareTo(normalized) >= 0 &&
          shard.rangeStart.compareTo(upperBound) <= 0;
    });
    final entries = await Future.wait(matchingShards.map(_loadShard));
    final seenHeadwords = <String>{};
    final suggestions = entries
        .expand((shard) => shard)
        .where((entry) => entry.normalizedKey.startsWith(normalized))
        .where((entry) => seenHeadwords.add(entry.normalizedKey))
        .take(limit)
        .toList(growable: false);
    return List<DictionaryEntry>.unmodifiable(suggestions);
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

  DictionaryShard _takeWeightedShard(List<DictionaryShard> candidates) {
    final totalRecords = candidates.fold<int>(
      0,
      (total, shard) => total + shard.recordCount,
    );
    var ticket = _random.nextInt(totalRecords);
    for (var index = 0; index < candidates.length; index++) {
      final shard = candidates[index];
      if (ticket < shard.recordCount) return candidates.removeAt(index);
      ticket -= shard.recordCount;
    }
    return candidates.removeLast();
  }

  void _sampleEntries(
    List<DictionaryEntry> entries,
    int targetCount,
    Set<String> seenHeadwords,
    List<DictionaryEntry> results,
  ) {
    if (entries.isEmpty) return;
    final maxAttempts = math.max(entries.length, targetCount * 10);
    for (var attempt = 0;
        attempt < maxAttempts && results.length < targetCount;
        attempt++) {
      final entry = entries[_random.nextInt(entries.length)];
      if (seenHeadwords.add(entry.normalizedKey)) results.add(entry);
    }
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

String _dictionaryPrefix(String normalized) {
  if (normalized.isEmpty) return 'other';
  final codeUnit = normalized.codeUnitAt(0);
  return codeUnit >= 97 && codeUnit <= 122
      ? String.fromCharCode(codeUnit)
      : 'other';
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
