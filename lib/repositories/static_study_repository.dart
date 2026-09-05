import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../models/study_models.dart';
import 'static_content_repository.dart';

class StaticStudyRepository {
  StaticStudyRepository(
      {AssetBundle? bundle, this.root = 'assets/content/study'})
      : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  final String root;
  Future<List<StudyModuleSummary>>? _modulesFuture;
  final Map<String, Future<StudyModuleDetail>> _moduleCache =
      <String, Future<StudyModuleDetail>>{};

  Future<List<StudyModuleSummary>> loadModules() =>
      _modulesFuture ??= _loadModules();

  Future<StudyModuleDetail> loadModule(String id) {
    return _moduleCache.putIfAbsent(id, () async {
      final module = (await loadModules()).where((item) => item.id == id);
      if (module.isEmpty) {
        throw StaticContentException('Çalışma modülü bulunamadı: $id');
      }
      final payload = await _loadJson(module.first.file);
      final detail = StudyModuleDetail.fromJson(payload);
      if (detail.module.id != id) {
        throw StaticContentException('Çalışma modülü verisi geçersiz: $id');
      }
      return detail;
    });
  }

  Future<List<StudyModuleSummary>> _loadModules() async {
    final manifest = await _loadJson('study_manifest.json');
    final counts = _map(manifest['counts']);
    if (counts['modules'] is! int || (counts['modules'] as int) < 1) {
      throw const StaticContentException('Çalışma manifest sayıları geçersiz.');
    }
    final modules = ((manifest['modules'] as List<Object?>?) ??
            const <Object?>[])
        .map((item) => StudyModuleSummary.fromJson(_map(item)))
        .toList(growable: false)
      ..sort((left, right) => left.number.compareTo(right.number));
    if (modules.length != counts['modules'] ||
        modules.map((item) => item.id).toSet().length != modules.length) {
      throw const StaticContentException('Çalışma modül indeksi geçersiz.');
    }
    return List<StudyModuleSummary>.unmodifiable(modules);
  }

  Future<Map<String, Object?>> _loadJson(String relativePath) async {
    try {
      final decoded =
          jsonDecode(await _bundle.loadString('$root/$relativePath'));
      if (decoded is! Map) {
        throw const FormatException('JSON object bekleniyordu.');
      }
      return Map<String, Object?>.from(decoded);
    } catch (error) {
      if (error is StaticContentException) rethrow;
      throw StaticContentException(
          'Çalışma asseti yüklenemedi: $relativePath', error);
    }
  }
}

Map<String, Object?> _map(Object? value) =>
    Map<String, Object?>.from(value! as Map);
