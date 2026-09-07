import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../models/test_models.dart';
import 'static_content_repository.dart';
import 'test_web_asset_loader.dart' as web_assets;

class StaticTestRepository {
  StaticTestRepository({
    AssetBundle? bundle,
    this.root = 'assets/content/tests',
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
  Future<TestBankManifest>? _manifestFuture;
  Future<List<TestModuleSummary>>? _modulesFuture;
  Future<TestStructureBank>? _structuresFuture;
  Future<List<TestExamSummary>>? _examsFuture;
  final Map<int, Future<TestModuleDetail>> _moduleCache = {};
  final Map<int, Future<TestExam>> _examCache = {};

  Future<TestBankManifest> loadManifest() {
    final pending = _manifestFuture;
    if (pending != null) return pending;
    final future = _loadManifest();
    _manifestFuture = future;
    future.then((_) {}, onError: (_) {
      _manifestFuture = null;
    });
    return future;
  }

  Future<List<TestModuleSummary>> loadModules() {
    final pending = _modulesFuture;
    if (pending != null) return pending;
    final future = _loadModules();
    _modulesFuture = future;
    future.then((_) {}, onError: (_) {
      _modulesFuture = null;
    });
    return future;
  }

  Future<TestModuleDetail> loadModule(int moduleNo) {
    final pending = _moduleCache[moduleNo];
    if (pending != null) return pending;
    final future = _fetchModule(moduleNo);
    _moduleCache[moduleNo] = future;
    future.then((_) {}, onError: (_) {
      _moduleCache.remove(moduleNo);
    });
    return future;
  }

  Future<TestModuleDetail> _fetchModule(int moduleNo) async {
    final summary = (await loadModules())
        .where((item) => item.moduleNo == moduleNo)
        .firstOrNull;
    if (summary == null) {
      throw StaticContentException('Testler modülü bulunamadı: $moduleNo');
    }
    final detail = TestModuleDetail.fromJson(await _loadJson(summary.file));
    if (detail.moduleNo != moduleNo) {
      throw const StaticContentException('Testler modül verisi geçersiz.');
    }
    return detail;
  }

  Future<TestStructureBank> loadStructures() {
    final pending = _structuresFuture;
    if (pending != null) return pending;
    final future = _loadStructures();
    _structuresFuture = future;
    future.then((_) {}, onError: (_) {
      _structuresFuture = null;
    });
    return future;
  }

  Future<List<TestExamSummary>> loadExams() {
    final pending = _examsFuture;
    if (pending != null) return pending;
    final future = _loadExams();
    _examsFuture = future;
    future.then((_) {}, onError: (_) {
      _examsFuture = null;
    });
    return future;
  }

  Future<TestExam> loadExam(int testNo) {
    final pending = _examCache[testNo];
    if (pending != null) return pending;
    final future = _fetchExam(testNo);
    _examCache[testNo] = future;
    future.then((_) {}, onError: (_) {
      _examCache.remove(testNo);
    });
    return future;
  }

  Future<TestExam> _fetchExam(int testNo) async {
    final summary = (await loadExams())
        .where((item) => item.testNo == testNo)
        .firstOrNull;
    if (summary == null) {
      throw StaticContentException('Özgün test bulunamadı: $testNo');
    }
    final exam = TestExam.fromJson(await _loadJson(summary.file));
    if (exam.testNo != testNo) {
      throw const StaticContentException('Özgün test verisi geçersiz.');
    }
    return exam;
  }

  Future<TestQuestionContentContract> loadQuestionContentContract() async {
    final manifest = await loadManifest();
    final raw = await _loadJson('test_bank_manifest.json');
    final content = _map(raw['questionContent']);
    final version = _text(content['version']);
    final fingerprints = _map(content['fingerprints']).map(
      (key, value) => MapEntry(key, _text(value)),
    );
    if (version.isEmpty ||
        fingerprints.isEmpty ||
        manifest.sourceHash != version) {
      throw const StaticContentException(
          'Testler soru sürüm bilgisi geçersiz.');
    }
    return TestQuestionContentContract(
      version: version,
      fingerprints: Map<String, String>.unmodifiable(fingerprints),
    );
  }

  Future<TestBankManifest> _loadManifest() async =>
      TestBankManifest.fromJson(await _loadJson('test_bank_manifest.json'));

  Future<List<TestModuleSummary>> _loadModules() async {
    final manifest = await loadManifest();
    final modules = List<TestModuleSummary>.of(manifest.modules)
      ..sort((left, right) => left.moduleNo.compareTo(right.moduleNo));
    if (modules.length != manifest.counts.modules ||
        modules.map((item) => item.moduleNo).toSet().length != modules.length) {
      throw const StaticContentException('Testler modül indeksi geçersiz.');
    }
    return List<TestModuleSummary>.unmodifiable(modules);
  }

  Future<TestStructureBank> _loadStructures() async {
    final manifest = await loadManifest();
    final bank = TestStructureBank.fromJson(
      await _loadJson(manifest.structuresFile),
    );
    if (bank.structures.length != manifest.counts.structures) {
      throw const StaticContentException('Testler yapı içeriği eksik.');
    }
    return bank;
  }

  Future<List<TestExamSummary>> _loadExams() async {
    final manifest = await loadManifest();
    final exams = List<TestExamSummary>.of(manifest.exams)
      ..sort((left, right) => left.testNo.compareTo(right.testNo));
    if (exams.length != manifest.counts.exams ||
        exams.map((item) => item.testNo).toSet().length != exams.length) {
      throw const StaticContentException('Özgün test indeksi geçersiz.');
    }
    return List<TestExamSummary>.unmodifiable(exams);
  }

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
          'Testler asseti yüklenemedi: $relativePath', error);
    }
  }

  Future<String> _loadString(String relativePath) {
    if (kIsWeb && _versionAssetLoads && _appBuildSha.isNotEmpty) {
      return web_assets.loadVersionedTestWebAsset(
        root: root,
        relativePath: relativePath,
        buildSha: _appBuildSha,
      );
    }
    final key = '$root/$relativePath';
    return _bundle.loadString(
      !_versionAssetLoads || _appBuildSha.isEmpty
          ? key
          : '$key?v=$_appBuildSha',
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

Map<String, Object?> _map(Object? value) =>
    Map<String, Object?>.from(value! as Map);

String _text(Object? value) => value?.toString().trim() ?? '';
