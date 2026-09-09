import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../models/content_models.dart';

class StaticContentException implements Exception {
  const StaticContentException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'DATA_LOAD_ERROR: $message';
}

class StaticContentRepository {
  StaticContentRepository(
      {AssetBundle? bundle, this.root = 'assets/content/v1'})
      : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  final String root;
  Future<_ContentManifest>? _manifestFuture;
  Future<Map<String, String>>? _legacyMapFuture;
  Future<List<WordEntry>>? _wordsFuture;
  Future<List<ReadingPassage>>? _readingsFuture;
  final Map<String, Future<ReadingDetail>> _readingCache =
      <String, Future<ReadingDetail>>{};

  Future<List<ContentPack>> loadPacks() async => (await _manifest()).packs;

  Future<List<WordEntry>> loadWords() {
    final pending = _wordsFuture;
    if (pending != null) return pending;
    final future = _loadWords();
    _wordsFuture = future;
    // Başarısız Future cache'de kalmasın; Tekrar dene yeniden yüklesin.
    future.then((_) {}, onError: (_) {
      _wordsFuture = null;
    });
    return future;
  }

  /// The reading index is intentionally separate from the word bootstrap
  /// path. Opening Kelimeler now loads only the manifest and word packs;
  /// the 800-item reading index is fetched when Okuma is actually visited.
  Future<List<ReadingPassage>> loadReadings() {
    final pending = _readingsFuture;
    if (pending != null) return pending;
    final future = _loadReadings();
    _readingsFuture = future;
    future.then((_) {}, onError: (_) {
      _readingsFuture = null;
    });
    return future;
  }

  Future<ReadingDetail> loadReading(String id) {
    final pending = _readingCache[id];
    if (pending != null) return pending;
    final future = _loadReading(id);
    _readingCache[id] = future;
    future.then((_) {}, onError: (_) {
      _readingCache.remove(id);
    });
    return future;
  }

  Future<ReadingDetail> _loadReading(String id) async {
    final passage =
        (await loadReadings()).where((item) => item.id == id).firstOrNull;
    if (passage == null || passage.file == null) {
      throw StaticContentException('Okuma kaydi bulunamadi: $id');
    }
    final payload = await _loadJson(passage.file!);
    final detail = ReadingDetail.fromJson(payload);
    if (detail.passage.id != id) {
      throw StaticContentException('Okuma cümleleri geçersiz: $id');
    }
    return detail;
  }

  Future<_ContentManifest> _manifest() {
    final pending = _manifestFuture;
    if (pending != null) return pending;
    final future = _loadManifest();
    _manifestFuture = future;
    future.then((_) {}, onError: (_) {
      _manifestFuture = null;
    });
    return future;
  }

  Future<_ContentManifest> _loadManifest() async {
    final manifest = await _loadJson('manifest.json');
    final counts = _jsonMap(manifest['counts']);
    if (counts['words'] != 9000 ||
        counts['readings'] is! int ||
        (counts['readings'] as int) < 1 ||
        counts['sentences'] is! int ||
        (counts['sentences'] as int) < 1) {
      throw StaticContentException('İçerik manifest sayıları doğrulanamadı.');
    }
    final packs = ((manifest['packs'] as List<Object?>?) ?? const <Object?>[])
        .map((item) => ContentPack.fromJson(_jsonMap(item)))
        .toList(growable: false);
    return _ContentManifest(
      packs: List<ContentPack>.unmodifiable(packs),
      readingCount: counts['readings']! as int,
      readingsIndex: manifest['readingsIndex']! as String,
      wordsIndex: manifest['wordsIndex']! as String,
      legacyReadingIdMap: manifest['legacyReadingIdMap'] as String?,
    );
  }

  Future<List<ReadingPassage>> _loadReadings() async {
    final content = await _manifest();
    final readingIndex = await _loadJson(content.readingsIndex);
    final readings =
        ((readingIndex['readings'] as List<Object?>?) ?? const <Object?>[])
            .map((item) => ReadingPassage.fromJson(_jsonMap(item)))
            .toList(growable: false);
    if (readings.length != content.readingCount) {
      throw StaticContentException('Okuma indeksi eksik veya bozuk.');
    }
    return List<ReadingPassage>.unmodifiable(readings);
  }

  /// Best-effort legacy (001–678) passage-ID migration map; missing file
  /// simply means there is nothing to migrate.
  Future<Map<String, String>> loadLegacyReadingIdMap() {
    final pending = _legacyMapFuture;
    if (pending != null) return pending;
    final future = _loadLegacyReadingIdMap();
    _legacyMapFuture = future;
    future.then((_) {}, onError: (_) {
      _legacyMapFuture = null;
    });
    return future;
  }

  Future<Map<String, String>> _loadLegacyReadingIdMap() async {
    try {
      final file = (await _manifest()).legacyReadingIdMap;
      if (file == null || file.isEmpty) return const <String, String>{};
      final payload = await _loadJson(file);
      final mapping = (payload['mapping'] as Map?) ?? const <String, String>{};
      return Map<String, String>.unmodifiable(
        mapping.map((key, value) => MapEntry(key.toString(), value.toString())),
      );
    } catch (_) {
      return const <String, String>{};
    }
  }

  Future<List<WordEntry>> _loadWords() async {
    final manifest = await _manifest();
    final index = await _loadJson(manifest.wordsIndex);
    final packFiles = ((index['packs'] as List<Object?>?) ?? const <Object?>[])
        .map(_jsonMap)
        .toList(growable: false);
    final chunks = await Future.wait(packFiles.map((pack) async {
      final content = await _loadJson(pack['file']! as String);
      return ((content['words'] as List<Object?>?) ?? const <Object?>[])
          .map((item) => WordEntry.fromJson(_jsonMap(item)))
          .toList(growable: false);
    }));
    final result = chunks.expand((chunk) => chunk).toList(growable: false)
      ..sort((left, right) => left.enWord.compareTo(right.enWord));
    if (result.length != 9000 ||
        result.map((item) => item.id).toSet().length != result.length) {
      throw StaticContentException('Kelime indeksi eksik veya bozuk.');
    }
    return List<WordEntry>.unmodifiable(result);
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

class _ContentManifest {
  const _ContentManifest({
    required this.packs,
    required this.readingCount,
    required this.readingsIndex,
    required this.wordsIndex,
    required this.legacyReadingIdMap,
  });

  final List<ContentPack> packs;
  final int readingCount;
  final String readingsIndex;
  final String wordsIndex;
  final String? legacyReadingIdMap;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

Map<String, Object?> _jsonMap(Object? value) =>
    Map<String, Object?>.from(value! as Map);
