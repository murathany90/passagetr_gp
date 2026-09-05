import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passagetr_gp/core/app_theme.dart';
import 'package:passagetr_gp/core/content_providers.dart';
import 'package:passagetr_gp/core/local_progress.dart';
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
    expect(modules, hasLength(12));
    expect(
      modules.map((item) => item.id),
      equals(<String>[
        for (var number = 1; number <= 12; number++)
          'study-${number.toString().padLeft(4, '0')}',
      ]),
    );
    expect(detail.words, hasLength(15));
    expect(detail.sentences, hasLength(5));
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
    for (final module in modules) {
      final routeDetail = await repository.loadModule(module.id);
      expect(routeDetail.module.id, module.id);
      expect(routeDetail.words, hasLength(15));
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
    }
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

    expect(find.text('Modül 1'), findsOneWidget);
    expect(find.text('Ana konu'), findsOneWidget);
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

class _MemoryProgress extends LocalProgressRepository {
  LocalProgressSnapshot _state = const LocalProgressSnapshot(isLoaded: true);

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
  Future<List<StudyModuleSummary>> loadModules() async =>
      const <StudyModuleSummary>[
        StudyModuleSummary(
          id: 'study-0001',
          number: 1,
          mainTopic: 'Çevre, İklim ve Enerji',
          subtopic: 'Power Grid Resilience & Energy Transition',
          grammarFocus: 'Participles & Reductions',
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
}
