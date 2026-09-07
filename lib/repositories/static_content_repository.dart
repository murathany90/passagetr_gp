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
  Future<_Catalog>? _catalogFuture;
  Future<Map<String, String>>? _legacyMapFuture;
  Future<List<WordEntry>>? _wordsFuture;
  final Map<String, Future<ReadingDetail>> _readingCache =
      <String, Future<ReadingDetail>>{};

  Future<List<ContentPack>> loadPacks() async => (await _catalog()).packs;

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

  Future<List<ReadingPassage>> loadReadings() async =>
      (await _catalog()).readings;

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

  Future<_Catalog> _catalog() {
    final pending = _catalogFuture;
    if (pending != null) return pending;
    final future = _loadCatalog();
    _catalogFuture = future;
    future.then((_) {}, onError: (_) {
      _catalogFuture = null;
    });
    return future;
  }

  Future<_Catalog> _loadCatalog() async {
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
    final readingIndex = await _loadJson(manifest['readingsIndex']! as String);
    final readings =
        ((readingIndex['readings'] as List<Object?>?) ?? const <Object?>[])
            .map((item) => ReadingPassage.fromJson(_jsonMap(item)))
            .toList(growable: false);
    if (readings.length != counts['readings']) {
      throw StaticContentException('Okuma indeksi eksik veya bozuk.');
    }
    return _Catalog(
      packs: packs,
      readings: List<ReadingPassage>.unmodifiable(readings),
      wordsIndex: manifest['wordsIndex']! as String,
    );
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
      final manifest = await _loadJson('manifest.json');
      final file = manifest['legacyReadingIdMap'] as String?;
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
    final catalog = await _catalog();
    final index = await _loadJson(catalog.wordsIndex);
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

class _Catalog {
  const _Catalog(
      {required this.packs, required this.readings, required this.wordsIndex});

  final List<ContentPack> packs;
  final List<ReadingPassage> readings;
  final String wordsIndex;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

Map<String, Object?> _jsonMap(Object? value) =>
    Map<String, Object?>.from(value! as Map);
