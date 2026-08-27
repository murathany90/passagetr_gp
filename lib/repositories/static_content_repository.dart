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
  Future<List<WordEntry>>? _wordsFuture;
  final Map<String, Future<ReadingDetail>> _readingCache =
      <String, Future<ReadingDetail>>{};

  Future<List<ContentPack>> loadPacks() async => (await _catalog()).packs;

  Future<List<WordEntry>> loadWords() => _wordsFuture ??= _loadWords();

  Future<List<ReadingPassage>> loadReadings() async =>
      (await _catalog()).readings;

  Future<ReadingDetail> loadReading(String id) {
    return _readingCache.putIfAbsent(id, () async {
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
    });
  }

  Future<_Catalog> _catalog() => _catalogFuture ??= _loadCatalog();

  Future<_Catalog> _loadCatalog() async {
    final manifest = await _loadJson('manifest.json');
    final counts = _jsonMap(manifest['counts']);
    if (counts['words'] != 5314 ||
        counts['readings'] != 678 ||
        counts['sentences'] != 5242) {
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
    if (readings.length != 678) {
      throw StaticContentException('Okuma indeksi eksik veya bozuk.');
    }
    return _Catalog(
      packs: packs,
      readings: List<ReadingPassage>.unmodifiable(readings),
      wordsIndex: manifest['wordsIndex']! as String,
    );
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
    if (result.length != 5314 ||
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
