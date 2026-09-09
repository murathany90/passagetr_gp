import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passagetr_gp/core/app_theme.dart';
import 'package:passagetr_gp/core/content_providers.dart';
import 'package:passagetr_gp/core/local_progress.dart';
import 'package:passagetr_gp/features/tests/tests_page.dart';
import 'package:passagetr_gp/models/test_models.dart';
import 'package:passagetr_gp/repositories/local_progress_repository.dart';
import 'package:passagetr_gp/repositories/static_test_repository.dart';

void main() {
  final repository = StaticTestRepository(bundle: _FileAssetBundle());

  test('Test Bank builds and validates canonical generated JSON', () async {
    final build =
        await Process.run('python', <String>['tools/build_test_content.py']);
    final validate = await Process.run(
      'python',
      <String>['tools/validate_test_content.py'],
    );
    expect(build.exitCode, 0, reason: build.stderr.toString());
    expect(validate.exitCode, 0, reason: validate.stderr.toString());
  });

  test('Test repository preserves canonical module rows and exam contracts',
      () async {
    final manifest = await repository.loadManifest();
    final modules = await repository.loadModules();
    final first = await repository.loadModule(1);
    final last = await repository.loadModule(110);
    final structures = await repository.loadStructures();
    final exams = await repository.loadExams();
    final exam = await repository.loadExam(1);
    final contract = await repository.loadQuestionContentContract();

    expect(
        manifest.canonicalSource, 'canonical/tests/passagetr_test_bank.xlsx');
    expect(manifest.counts.modules, 110);
    expect(manifest.counts.wordRows, 2200);
    expect(manifest.counts.uniqueHeadwords, 2165);
    expect(manifest.counts.structures, 480);
    expect(manifest.counts.exams, 9);
    expect(manifest.counts.questions, 450);
    expect(manifest.counts.options, 2250);
    expect(manifest.counts.optionTrMissing, 64);
    expect(modules, hasLength(110));
    expect(first.words, hasLength(20));
    expect(last.words, hasLength(20));
    expect(structures.structures, hasLength(480));
    expect(exams, hasLength(9));
    expect(exam.questions, hasLength(50));
    expect(contract.fingerprints, hasLength(450));
    expect(
      exam.questions.every(
        (question) =>
            question.question.isNotEmpty &&
            question.options.length == 5 &&
            question.options.any(
              (option) => option.textEn == question.correctAnswer,
            ),
      ),
      isTrue,
    );
  });

  test('Test deploy versioning keeps injected AssetBundle paths testable',
      () async {
    final bundle = _VersionedFileAssetBundle();
    final versioned = StaticTestRepository(
      bundle: bundle,
      appBuildSha: 'test-deploy-sha',
      versionAssetLoads: true,
    );
    await versioned.loadModule(110);
    expect(
      bundle.loadedKeys,
      contains(
          'assets/content/tests/test_bank_manifest.json?v=test-deploy-sha'),
    );
    expect(
      bundle.loadedKeys,
      contains(
          'assets/content/tests/modules/module_110.json?v=test-deploy-sha'),
    );
  });

  test('Test favourites resolve only from Test Bank module assets', () async {
    final module = await repository.loadModule(1);
    final words = await repository.loadWordsByIds(<String>[
      module.words.first.id,
    ]);

    expect(words, hasLength(1));
    expect(words.single.id, module.words.first.id);
  });

  test('Test content revision safely drops retired question progress',
      () async {
    final controller = LocalProgressController(_MemoryProgress(
      initial: const LocalProgressSnapshot(
        isLoaded: true,
        favoriteWordIds: <String>{'keep-favorite'},
        testQuestionAnswers: <String, String>{'test-01-q01': 'A'},
        testQuestionCorrectness: <String, bool>{'test-01-q01': false},
        testQuestionContentVersion: 'old-version',
        testQuestionFingerprints: <String, String>{},
      ),
    ));
    addTearDown(controller.dispose);

    await controller.reconcileTestQuestionContent(
      version: 'new-version',
      fingerprints: const <String, String>{'test-01-q02': 'fresh'},
    );

    expect(controller.state.testQuestionAnswers, isEmpty);
    expect(controller.state.testQuestionCorrectness, isEmpty);
    expect(controller.state.favoriteWordIds, <String>{'keep-favorite'});
  });

  test('Test module and exam reset keep unrelated local progress', () async {
    final controller = LocalProgressController(_MemoryProgress(
      initial: const LocalProgressSnapshot(
        isLoaded: true,
        favoriteWordIds: <String>{'keep-favorite'},
        testFavoriteWordIds: <String>{'test-module-001-word-01'},
        testLastModuleNo: 1,
        testFlashcardKnownIds: <String>{'module-1-word', 'module-2-word'},
        completedTestMatchingModuleIds: <String>{'1', '2'},
        testMatchingBestScores: <String, int>{'1': 80, '2': 60},
        testQuickTestBestScores: <String, int>{'1': 70, '2': 90},
        testKnownStructureIds: <String>{'structure-keep'},
        testQuestionAnswers: <String, String>{
          'test-01-q-001': 'A',
          'test-02-q-001': 'B',
        },
        testQuestionCorrectness: <String, bool>{
          'test-01-q-001': true,
          'test-02-q-001': false,
        },
        testQuestionFingerprints: <String, String>{
          'test-01-q-001': 'one',
          'test-02-q-001': 'two',
        },
        testExamLastQuestionIndexes: <String, int>{'1': 5, '2': 3},
        testExamBestScores: <String, int>{'1': 80, '2': 60},
      ),
    ));
    addTearDown(controller.dispose);
    await controller.restoreFuture;

    controller.resetTestModuleProgress(
      moduleNo: 1,
      wordIds: const <String>['module-1-word'],
    );
    controller.resetTestExamProgress(
      testNo: 1,
      questionIds: const <String>['test-01-q-001'],
    );

    expect(controller.state.favoriteWordIds, <String>{'keep-favorite'});
    expect(controller.state.testFavoriteWordIds,
        <String>{'test-module-001-word-01'});
    expect(controller.state.testFlashcardKnownIds, <String>{'module-2-word'});
    expect(controller.state.completedTestMatchingModuleIds, <String>{'2'});
    expect(controller.state.testMatchingBestScores, <String, int>{'2': 60});
    expect(controller.state.testQuickTestBestScores, <String, int>{'2': 90});
    expect(controller.state.testKnownStructureIds, <String>{'structure-keep'});
    expect(controller.state.testLastModuleNo, isNull);
    expect(
        controller.state.testQuestionAnswers.keys, <String>['test-02-q-001']);
    expect(controller.state.testExamLastQuestionIndexes, <String, int>{'2': 3});
    expect(controller.state.testExamBestScores, <String, int>{'2': 60});
  });

  test('Test favourites and activity records never mutate Words favourites',
      () async {
    final controller = LocalProgressController(_MemoryProgress(
      initial: const LocalProgressSnapshot(
        isLoaded: true,
        favoriteWordIds: <String>{'main-word'},
      ),
    ));
    addTearDown(controller.dispose);
    await controller.restoreFuture;

    controller.toggleTestFavoriteWord('test-module-001-word-01');
    controller.recordTestMatchingResult(
      moduleNo: 1,
      correct: 4,
      total: 5,
    );
    controller.recordTestQuickTestResult(
      moduleNo: 1,
      correct: 3,
      total: 5,
    );
    controller.markTestStructureKnown('structure-001');
    controller.markTestFlashcardKnown('test-module-001-word-01');
    controller.markTestFlashcardForReview('test-module-001-word-01');

    expect(controller.state.testFlashcardKnownIds, isEmpty);

    controller.completeTestModuleProgress(
      moduleNo: 1,
      wordIds: const <String>[
        'test-module-001-word-01',
        'test-module-001-word-02',
      ],
    );

    expect(controller.state.favoriteWordIds, <String>{'main-word'});
    expect(controller.state.testFavoriteWordIds,
        <String>{'test-module-001-word-01'});
    expect(controller.state.testFlashcardKnownIds, <String>{
      'test-module-001-word-01',
      'test-module-001-word-02',
    });
    expect(controller.state.completedTestMatchingModuleIds, <String>{'1'});
    expect(controller.state.testMatchingBestScores, <String, int>{'1': 100});
    expect(controller.state.testQuickTestBestScores, <String, int>{'1': 100});
    expect(controller.state.testKnownStructureIds, <String>{'structure-001'});
  });

  testWidgets('Testler main page is compact at 360, 390 and 430 px',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final width in <double>[360, 390, 430]) {
      await tester.binding.setSurfaceSize(Size(width, 844));
      await tester.pumpWidget(ProviderScope(
        overrides: <Override>[
          staticTestRepositoryProvider
              .overrideWithValue(_TestFixtureRepository()),
          testQuestionCompatibilityProvider.overrideWith((ref) async {}),
          localProgressRepositoryProvider.overrideWithValue(_MemoryProgress()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: TestsPage()),
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.text('Testler'), findsOneWidget);
      expect(find.text('1–10'), findsOneWidget);
      expect(find.text('101–110'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}

class _FileAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bytes = await File(key).readAsBytes();
    return ByteData.sublistView(bytes);
  }
}

class _VersionedFileAssetBundle extends CachingAssetBundle {
  final List<String> loadedKeys = <String>[];

  @override
  Future<ByteData> load(String key) async {
    loadedKeys.add(key);
    final bytes = await File(key.split('?').first).readAsBytes();
    return ByteData.sublistView(bytes);
  }
}

class _MemoryProgress extends LocalProgressRepository {
  _MemoryProgress({LocalProgressSnapshot? initial})
      : _snapshot = initial ?? const LocalProgressSnapshot(isLoaded: true);

  LocalProgressSnapshot _snapshot;

  @override
  Future<LocalProgressSnapshot> load() async => _snapshot;

  @override
  Future<void> saveTestQuestionAnswers(Map<String, String> answers) async {
    _snapshot = _snapshot.copyWith(testQuestionAnswers: answers);
  }

  @override
  Future<void> saveTestQuestionCorrectness(
      Map<String, bool> correctness) async {
    _snapshot = _snapshot.copyWith(testQuestionCorrectness: correctness);
  }

  @override
  Future<void> saveTestQuestionContent({
    required String version,
    required Map<String, String> fingerprints,
  }) async {
    _snapshot = _snapshot.copyWith(
      testQuestionContentVersion: version,
      testQuestionFingerprints: fingerprints,
    );
  }

  @override
  Future<void> saveTestLastModuleNo(int? moduleNo) async {
    _snapshot = _snapshot.copyWith(
      testLastModuleNo: moduleNo,
      clearTestLastModuleNo: moduleNo == null,
    );
  }

  @override
  Future<void> saveTestFlashcardKnownIds(Set<String> ids) async {
    _snapshot = _snapshot.copyWith(testFlashcardKnownIds: ids);
  }

  @override
  Future<void> saveCompletedTestMatchingModuleIds(Set<String> ids) async {
    _snapshot = _snapshot.copyWith(completedTestMatchingModuleIds: ids);
  }

  @override
  Future<void> saveTestFavoriteWordIds(Set<String> ids) async {
    _snapshot = _snapshot.copyWith(testFavoriteWordIds: ids);
  }

  @override
  Future<void> saveTestMatchingBestScores(Map<String, int> scores) async {
    _snapshot = _snapshot.copyWith(testMatchingBestScores: scores);
  }

  @override
  Future<void> saveTestQuickTestBestScores(Map<String, int> scores) async {
    _snapshot = _snapshot.copyWith(testQuickTestBestScores: scores);
  }

  @override
  Future<void> saveTestKnownStructureIds(Set<String> ids) async {
    _snapshot = _snapshot.copyWith(testKnownStructureIds: ids);
  }

  @override
  Future<void> saveTestExamLastQuestionIndexes(Map<String, int> indexes) async {
    _snapshot = _snapshot.copyWith(testExamLastQuestionIndexes: indexes);
  }

  @override
  Future<void> saveTestExamBestScores(Map<String, int> scores) async {
    _snapshot = _snapshot.copyWith(testExamBestScores: scores);
  }
}

class _TestFixtureRepository extends StaticTestRepository {
  @override
  Future<TestBankManifest> loadManifest() async => TestBankManifest(
        canonicalSource: 'canonical/tests/passagetr_test_bank.xlsx',
        sourceHash: 'fixture',
        counts: const TestBankCounts(
          modules: 110,
          wordRows: 2200,
          uniqueHeadwords: 2165,
          structures: 480,
          structureCategories: 5,
          exams: 9,
          questions: 450,
          options: 2250,
          optionTrCovered: 2186,
          optionTrMissing: 64,
        ),
        modules: await loadModules(),
        structuresFile: 'structures.json',
        exams: const <TestExamSummary>[],
      );

  @override
  Future<List<TestModuleSummary>> loadModules() async => List.generate(
        110,
        (index) => TestModuleSummary(
          id: 'module-${(index + 1).toString().padLeft(3, '0')}',
          moduleNo: index + 1,
          wordCount: 20,
          file: 'modules/module_${(index + 1).toString().padLeft(3, '0')}.json',
        ),
      );
}
