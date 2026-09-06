import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passagetr_gp/core/app_theme.dart';
import 'package:passagetr_gp/core/content_providers.dart';
import 'package:passagetr_gp/core/local_progress.dart';
import 'package:passagetr_gp/features/study/study_module_page.dart';
import 'package:passagetr_gp/features/study/study_page.dart';
import 'package:passagetr_gp/models/study_models.dart';
import 'package:passagetr_gp/repositories/local_progress_repository.dart';
import 'package:passagetr_gp/repositories/static_study_repository.dart';

void main() {
  final repository = StaticStudyRepository(bundle: _FileAssetBundle());

  test('canonical study workbook builds and validates bundled JSON', () async {
    final build =
        await Process.run('python', <String>['tools/build_study_content.py']);
    final validate = await Process.run(
        'python', <String>['tools/validate_study_content.py']);
    expect(build.exitCode, 0, reason: build.stderr.toString());
    expect(validate.exitCode, 0, reason: validate.stderr.toString());
  });

  test('study repository loads all generated Study modules', () async {
    final modules = await repository.loadModules();
    final detail = await repository.loadModule('study-0001');
    expect(modules, hasLength(30));
    expect(
      modules.map((item) => item.id),
      equals(<String>[
        for (var number = 1; number <= 30; number++)
          'study-${number.toString().padLeft(4, '0')}',
      ]),
    );
    expect(detail.words, hasLength(15));
    expect(detail.sentences, hasLength(5));
    expect(detail.module.subtopicTr, isNotEmpty);
    expect(detail.module.grammarFocusTr, isNotEmpty);
    expect(detail.reading.titleTr, isNotEmpty);
    expect(detail.reading.sentencePairs, isNotEmpty);
    expect(
      detail.reading.sentencePairs.every(
        (item) => item.english.isNotEmpty && item.turkish.isNotEmpty,
      ),
      isTrue,
    );
    expect(detail.reading.questions, hasLength(5));
    expect(detail.translations.enTr, hasLength(7));
    expect(detail.translations.trEn, hasLength(7));
    expect(detail.testQuestions, hasLength(10));
    expect(detail.review, hasLength(29));
    final activeRecall = detail.review.where(
      (item) =>
          item.type == 'active_recall_en' || item.type == 'active_recall_tr',
    );
    expect(activeRecall, hasLength(10));
    expect(
      activeRecall.every(
        (item) => item.type == 'active_recall_en'
            ? item.answerEn.isNotEmpty
            : item.answerTr.isNotEmpty,
      ),
      isTrue,
    );
    var usageNoteCount = 0;
    var translationStrategyCount = 0;
    for (final module in modules) {
      final routeDetail = await repository.loadModule(module.id);
      expect(routeDetail.module.id, module.id);
      expect(routeDetail.words, hasLength(15));
      expect(routeDetail.reading.sentencePairs, isNotEmpty);
      expect(
        routeDetail.reading.sentencePairs.every(
          (item) => item.english.isNotEmpty && item.turkish.isNotEmpty,
        ),
        isTrue,
      );
      expect(routeDetail.reading.questions, hasLength(5));
      final routeRecall = routeDetail.review.where(
        (item) =>
            item.type == 'active_recall_en' || item.type == 'active_recall_tr',
      );
      expect(
        routeRecall.every(
          (item) => item.type == 'active_recall_en'
              ? item.answerEn.isNotEmpty
              : item.answerTr.isNotEmpty,
        ),
        isTrue,
      );
      usageNoteCount += routeDetail.words
          .expand((word) => word.items)
          .where((item) => item.usageNote.isNotEmpty)
          .length;
      translationStrategyCount += routeDetail.sentences
          .where(
            (sentence) => sentence.analysis.containsKey('Çeviri stratejisi'),
          )
          .length;
    }
    expect(usageNoteCount, 120);
    expect(translationStrategyCount, 150);
    final contract = await repository.loadQuestionContentContract();
    expect(contract.version, isNotEmpty);
    expect(contract.fingerprints, hasLength(450));
    expect(
      contract.fingerprints['study-0001-yq01'],
      detail.testQuestions.first.contentFingerprint,
    );
  });

  test('Study deploy versioning preserves injected AssetBundle paths',
      () async {
    final bundle = _VersionedFileAssetBundle();
    final versionedRepository = StaticStudyRepository(
      bundle: bundle,
      appBuildSha: 'deploy-sha',
      versionAssetLoads: true,
    );

    await versionedRepository.loadModule('study-0030');

    expect(
      bundle.loadedKeys,
      contains('assets/content/study/study_manifest.json?v=deploy-sha'),
    );
    expect(
      bundle.loadedKeys,
      contains('assets/content/study/modules/study_0030.json?v=deploy-sha'),
    );

    final plainBundle = _VersionedFileAssetBundle();
    final injectedRepository = StaticStudyRepository(
      bundle: plainBundle,
      appBuildSha: 'deploy-sha',
    );
    await injectedRepository.loadModules();
    expect(
      plainBundle.loadedKeys,
      contains('assets/content/study/study_manifest.json'),
    );
    expect(
      plainBundle.loadedKeys,
      isNot(contains('assets/content/study/study_manifest.json?v=deploy-sha')),
    );
  });

  test('resetting one Study module preserves other module progress', () {
    final controller = LocalProgressController(_MemoryProgress());
    addTearDown(controller.dispose);
    controller.toggleFavoriteWord('word-keep');
    controller.setStudyLocation(moduleId: 'study-0001', section: 'test');
    controller.markStudySectionCompleted(
      moduleId: 'study-0001',
      section: 'reading',
      sectionCount: 1,
    );
    controller.markStudySectionCompleted(
      moduleId: 'study-0002',
      section: 'reading',
      sectionCount: 1,
    );
    controller.answerStudyQuestion(
      questionId: 'study-0001-yq01',
      answer: 'A',
      isCorrect: true,
    );
    controller.answerStudyQuestion(
      questionId: 'study-0002-yq01',
      answer: 'B',
      isCorrect: false,
    );

    controller.resetStudyModuleProgress('study-0001');

    expect(controller.state.favoriteWordIds, contains('word-keep'));
    expect(controller.state.completedStudyModuleIds, {'study-0002'});
    expect(controller.state.completedStudySectionKeys, {'study-0002:reading'});
    expect(controller.state.studyQuestionAnswers, {'study-0002-yq01': 'B'});
    expect(
        controller.state.studyQuestionCorrectness, {'study-0002-yq01': false});
    expect(controller.state.studyLastModuleId, isNull);
    expect(controller.state.studyLastSection, isNull);
  });

  test('Study content revision retains only matching question fingerprints',
      () async {
    final repository = _MemoryProgress(
      initial: const LocalProgressSnapshot(
        isLoaded: true,
        favoriteWordIds: {'word-keep'},
        knownWordIds: {'word-known'},
        completedReadingIds: {'reading-keep'},
        studyQuestionAnswers: {
          'study-0001-yq01': 'A',
          'study-0001-yq02': 'B',
        },
        studyQuestionCorrectness: {
          'study-0001-yq01': true,
          'study-0001-yq02': false,
        },
        studyQuestionContentVersion: 'old-workbook',
        studyQuestionFingerprints: {
          'study-0001-yq01': 'unchanged',
          'study-0001-yq02': 'old-question',
        },
      ),
    );
    final controller = LocalProgressController(repository);
    addTearDown(controller.dispose);

    await controller.reconcileStudyQuestionContent(
      version: 'new-workbook',
      fingerprints: const {
        'study-0001-yq01': 'unchanged',
        'study-0001-yq02': 'new-question',
      },
    );

    expect(controller.state.favoriteWordIds, {'word-keep'});
    expect(controller.state.knownWordIds, {'word-known'});
    expect(controller.state.completedReadingIds, {'reading-keep'});
    expect(controller.state.studyQuestionAnswers, {'study-0001-yq01': 'A'});
    expect(
      controller.state.studyQuestionCorrectness,
      {'study-0001-yq01': true},
    );
    expect(controller.state.studyQuestionFingerprints, {
      'study-0001-yq01': 'unchanged',
    });
    expect(controller.state.studyQuestionContentVersion, 'new-workbook');
  });

  testWidgets('Study home opens at a 390 px viewport without overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[
        staticStudyRepositoryProvider
            .overrideWithValue(_StudyFixtureRepository()),
        localProgressRepositoryProvider.overrideWithValue(_MemoryProgress()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: StudyPage()),
      ),
    ));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Modül 01'), findsOneWidget);
    expect(find.text('Ana konu'), findsAtLeastNWidgets(1));
    expect(find.text('Gramer'), findsAtLeastNWidgets(1));
    expect(find.text('Seviye'), findsNothing);
    expect(find.text('Durum'), findsNothing);
    expect(
      find.text(
        'Power Grid Resilience & Energy Transition '
        '(Elektrik Şebekesi Dayanıklılığı ve Enerji Dönüşümü)',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Study home paginates 30 modules in groups of 10',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[
        staticStudyRepositoryProvider
            .overrideWithValue(_ManyStudyFixtureRepository()),
        localProgressRepositoryProvider.overrideWithValue(_MemoryProgress()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: StudyPage()),
      ),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('1–10'), findsOneWidget);
    expect(find.text('11–20'), findsOneWidget);
    expect(find.text('21–30'), findsOneWidget);
    expect(find.text('Modül 01'), findsOneWidget);
    expect(find.text('Modül 11'), findsNothing);

    await tester.tap(find.text('11–20'));
    await tester.pump();
    expect(find.text('Modül 11'), findsOneWidget);
    expect(find.text('Modül 01'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Study module uses a compact 4 + 3 tab grid at 390 px',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[
        staticStudyRepositoryProvider
            .overrideWithValue(_StudyFixtureRepository()),
        localProgressRepositoryProvider.overrideWithValue(_MemoryProgress()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: StudyModulePage(moduleId: 'study-0001')),
      ),
    ));
    await tester.pump();
    await tester.pump();

    for (final label in <String>[
      'Kelime',
      'Gramer',
      'Okuma',
      'Çeviri',
      'YDS',
      'Test',
      'Tekrar',
    ]) {
      expect(find.text(label), findsAtLeastNWidgets(1));
    }
    expect(tester.takeException(), isNull);
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
    final path = key.split('?').first;
    final bytes = await File(path).readAsBytes();
    return ByteData.sublistView(bytes);
  }
}

class _MemoryProgress extends LocalProgressRepository {
  _MemoryProgress({LocalProgressSnapshot? initial})
      : _state = initial ?? const LocalProgressSnapshot(isLoaded: true);

  LocalProgressSnapshot _state;

  @override
  Future<LocalProgressSnapshot> load() async => _state;

  @override
  Future<void> saveFavoriteWordIds(Set<String> ids) async {
    _state = _state.copyWith(favoriteWordIds: ids);
  }

  @override
  Future<void> saveStudyLocation({String? moduleId, String? section}) async {
    _state = _state.copyWith(
      studyLastModuleId: moduleId,
      studyLastSection: section,
    );
  }

  @override
  Future<void> saveStudyQuestionAnswers(Map<String, String> answers) async {
    _state = _state.copyWith(studyQuestionAnswers: answers);
  }

  @override
  Future<void> saveStudyQuestionCorrectness(
      Map<String, bool> correctness) async {
    _state = _state.copyWith(studyQuestionCorrectness: correctness);
  }

  @override
  Future<void> saveStudyQuestionContent({
    required String version,
    required Map<String, String> fingerprints,
  }) async {
    _state = _state.copyWith(
      studyQuestionContentVersion: version,
      studyQuestionFingerprints: fingerprints,
    );
  }

  @override
  Future<void> saveCompletedStudySectionKeys(Set<String> keys) async {
    _state = _state.copyWith(completedStudySectionKeys: keys);
  }

  @override
  Future<void> saveCompletedStudyModuleIds(Set<String> ids) async {
    _state = _state.copyWith(completedStudyModuleIds: ids);
  }
}

class _StudyFixtureRepository extends StaticStudyRepository {
  @override
  Future<StudyQuestionContentContract> loadQuestionContentContract() async =>
      const StudyQuestionContentContract(
        version: 'study-fixture-v1',
        fingerprints: <String, String>{},
      );

  @override
  Future<List<StudyModuleSummary>> loadModules() async =>
      const <StudyModuleSummary>[
        StudyModuleSummary(
          id: 'study-0001',
          number: 1,
          mainTopic: 'Çevre, İklim ve Enerji',
          subtopic: 'Power Grid Resilience & Energy Transition',
          subtopicTr: 'Elektrik Şebekesi Dayanıklılığı ve Enerji Dönüşümü',
          grammarFocus: 'Participles & Reductions',
          grammarFocusTr: 'Ortaçlar ve İndirgenmiş Yapılar',
          levelProfile: 'B2–C1',
          status: 'example',
          file: 'modules/study_0001.json',
          counts: StudyModuleCounts(
            words: 15,
            sentences: 5,
            readings: 1,
            translations: 14,
            testQuestions: 10,
          ),
        ),
      ];

  @override
  Future<StudyModuleDetail> loadModule(String moduleId) async {
    final module = (await loadModules()).single;
    return StudyModuleDetail(
      module: module,
      words: const <StudyWord>[],
      sentences: const <StudySentence>[],
      reading: const StudyReading(
        title: '',
        titleTr: '',
        textEn: '',
        textTr: '',
        sentencePairs: <StudyReadingSentence>[],
        mainIdeaTr: '',
        flowAnalysis: '',
        importantWords: '',
        connectorMap: '',
        referenceAnalysis: '',
        questions: <StudyQuestion>[],
      ),
      translations: const StudyTranslations(
        enTr: <StudyTranslation>[],
        trEn: <StudyTranslation>[],
      ),
      structures: const <StudyStructure>[],
      testQuestions: const <StudyQuestion>[],
      review: const <StudyReviewItem>[],
    );
  }
}

class _ManyStudyFixtureRepository extends _StudyFixtureRepository {
  @override
  Future<List<StudyModuleSummary>> loadModules() async => List.generate(
        30,
        (index) => StudyModuleSummary(
          id: 'study-${(index + 1).toString().padLeft(4, '0')}',
          number: index + 1,
          mainTopic: index.isEven ? 'Bilim' : 'Toplum',
          subtopic: 'Module ${index + 1}',
          subtopicTr: 'Modül ${index + 1}',
          grammarFocus: index.isEven ? 'Grammar A' : 'Grammar B',
          grammarFocusTr: index.isEven ? 'Gramer A' : 'Gramer B',
          levelProfile: 'B2',
          status: 'example',
          file: 'modules/study_${(index + 1).toString().padLeft(4, '0')}.json',
          counts: const StudyModuleCounts(
            words: 15,
            sentences: 5,
            readings: 1,
            translations: 14,
            testQuestions: 10,
          ),
        ),
      );

  @override
  Future<StudyModuleDetail> loadModule(String moduleId) async {
    final module = (await loadModules()).firstWhere(
      (item) => item.id == moduleId,
    );
    return StudyModuleDetail(
      module: module,
      words: const <StudyWord>[],
      sentences: const <StudySentence>[],
      reading: const StudyReading(
        title: '',
        titleTr: '',
        textEn: '',
        textTr: '',
        sentencePairs: <StudyReadingSentence>[],
        mainIdeaTr: '',
        flowAnalysis: '',
        importantWords: '',
        connectorMap: '',
        referenceAnalysis: '',
        questions: <StudyQuestion>[],
      ),
      translations: const StudyTranslations(
        enTr: <StudyTranslation>[],
        trEn: <StudyTranslation>[],
      ),
      structures: const <StudyStructure>[],
      testQuestions: const <StudyQuestion>[],
      review: const <StudyReviewItem>[],
    );
  }
}
