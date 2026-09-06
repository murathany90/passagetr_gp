import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../models/study_models.dart';
import 'static_content_repository.dart';
import 'study_web_asset_loader.dart' as web_assets;

class StaticStudyRepository {
  StaticStudyRepository({
    AssetBundle? bundle,
    this.root = 'assets/content/study',
    String? appBuildSha,
    bool? versionAssetLoads,
  })  : _bundle = bundle ?? rootBundle,
        _appBuildSha =
            (appBuildSha ?? const String.fromEnvironment('APP_BUILD_SHA'))
                .trim(),
        _versionAssetLoads = versionAssetLoads ?? bundle == null;

  final AssetBundle _bundle;
  final String root;
  final String _appBuildSha;
  final bool _versionAssetLoads;
  Future<Map<String, Object?>>? _manifestFuture;
  Future<List<StudyModuleSummary>>? _modulesFuture;
  final Map<String, Future<StudyModuleDetail>> _moduleCache =
      <String, Future<StudyModuleDetail>>{};

  Future<List<StudyModuleSummary>> loadModules() =>
      _modulesFuture ??= _loadModules();

  /// A stable content contract for safely retaining only answers that still
  /// belong to the current canonical Study questions after a workbook update.
  Future<StudyQuestionContentContract> loadQuestionContentContract() async {
    final manifest = await _loadManifest();
    final questionContent = _map(manifest['questionContent']);
    final version = _text(questionContent['version']);
    final rawFingerprints = _map(questionContent['fingerprints']);
    if (version.isEmpty || rawFingerprints.isEmpty) {
      throw const StaticContentException(
        'Çalışma soru sürüm bilgisi geçersiz.',
      );
    }
    return StudyQuestionContentContract(
      version: version,
      fingerprints: Map<String, String>.unmodifiable(
        rawFingerprints.map((key, value) => MapEntry(key, _text(value))),
      ),
    );
  }

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
    final manifest = await _loadManifest();
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

  Future<Map<String, Object?>> _loadManifest() =>
      _manifestFuture ??= _loadJson('study_manifest.json');

  Future<Map<String, Object?>> _loadJson(String relativePath) async {
    try {
      final decoded = jsonDecode(await _loadString(relativePath));
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

  String _assetKey(String relativePath) {
    final key = '$root/$relativePath';
    if (!_versionAssetLoads || _appBuildSha.isEmpty) return key;
    return '$key?v=${Uri.encodeQueryComponent(_appBuildSha)}';
  }

  Future<String> _loadString(String relativePath) {
    if (kIsWeb && _versionAssetLoads && _appBuildSha.isNotEmpty) {
      // Flutter's rootBundle resolves logical asset keys, where a query string
      // is treated as part of the filename. The web loader fetches the
      // physical asset URL so each deployment gets its own cache key.
      return web_assets.loadVersionedStudyWebAsset(
        root: root,
        relativePath: relativePath,
        buildSha: _appBuildSha,
      );
    }
    return _bundle.loadString(_assetKey(relativePath));
  }
}

class StudyQuestionContentContract {
  const StudyQuestionContentContract({
    required this.version,
    required this.fingerprints,
  });

  final String version;
  final Map<String, String> fingerprints;
}

Map<String, Object?> _map(Object? value) =>
    Map<String, Object?>.from(value! as Map);

String _text(Object? value) => value?.toString().trim() ?? '';
