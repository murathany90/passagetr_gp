import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/local_progress_repository.dart';

final localProgressRepositoryProvider = Provider<LocalProgressRepository>(
  (ref) => LocalProgressRepository(),
);

final localProgressProvider =
    StateNotifierProvider<LocalProgressController, LocalProgressSnapshot>(
  (ref) => LocalProgressController(ref.watch(localProgressRepositoryProvider)),
);

class LocalProgressController extends StateNotifier<LocalProgressSnapshot> {
  LocalProgressController(this._repository)
      : super(const LocalProgressSnapshot.empty()) {
    _restoreFuture = _restore();
  }

  final LocalProgressRepository _repository;
  late final Future<void> _restoreFuture;
  bool _changedBeforeRestore = false;

  Future<void> _restore() async {
    try {
      final restored = await _repository.load();
      if (mounted && !_changedBeforeRestore) {
        state = restored;
      }
    } catch (_) {
      if (mounted) {
        state = state.copyWith(isLoaded: true);
      }
    }
  }

  void setWordFilters({String? tag, String? level}) {
    _changedBeforeRestore = true;
    state = state.copyWith(
      isLoaded: true,
      wordTag: tag,
      clearWordTag: tag == null,
      wordLevel: level,
      clearWordLevel: level == null,
    );
    unawaited(_repository.saveWordFilters(tag: tag, level: level));
  }

  void setReadingFilters({String? level, String? category}) {
    _changedBeforeRestore = true;
    state = state.copyWith(
      isLoaded: true,
      readingLevel: level,
      clearReadingLevel: level == null,
      readingCategory: category,
      clearReadingCategory: category == null,
    );
    unawaited(_repository.saveReadingFilters(level: level, category: category));
  }

  void toggleFavoriteWord(String wordId) {
    _changedBeforeRestore = true;
    final ids = Set<String>.of(state.favoriteWordIds);
    ids.contains(wordId) ? ids.remove(wordId) : ids.add(wordId);
    state =
        state.copyWith(isLoaded: true, favoriteWordIds: Set.unmodifiable(ids));
    unawaited(_repository.saveFavoriteWordIds(ids));
  }

  void markWordKnown(String wordId) {
    if (state.knownWordIds.contains(wordId)) {
      return;
    }
    _changedBeforeRestore = true;
    final ids = Set<String>.of(state.knownWordIds)..add(wordId);
    state = state.copyWith(isLoaded: true, knownWordIds: Set.unmodifiable(ids));
    unawaited(_repository.saveKnownWordIds(ids));
  }

  void toggleReadingCompleted(String readingId) {
    _changedBeforeRestore = true;
    final ids = Set<String>.of(state.completedReadingIds);
    ids.contains(readingId) ? ids.remove(readingId) : ids.add(readingId);
    state = state.copyWith(
        isLoaded: true, completedReadingIds: Set.unmodifiable(ids));
    unawaited(_repository.saveCompletedReadingIds(ids));
  }

  void setStudyLocation({required String moduleId, required String section}) {
    _changedBeforeRestore = true;
    state = state.copyWith(
      isLoaded: true,
      studyLastModuleId: moduleId,
      studyLastSection: section,
    );
    unawaited(_repository.saveStudyLocation(
      moduleId: moduleId,
      section: section,
    ));
  }

  void answerStudyQuestion({
    required String questionId,
    required String answer,
    required bool isCorrect,
    String? contentFingerprint,
  }) {
    _changedBeforeRestore = true;
    final answers = Map<String, String>.of(state.studyQuestionAnswers)
      ..[questionId] = answer;
    final correctness = Map<String, bool>.of(state.studyQuestionCorrectness)
      ..[questionId] = isCorrect;
    final fingerprints =
        Map<String, String>.of(state.studyQuestionFingerprints);
    if (contentFingerprint != null && contentFingerprint.isNotEmpty) {
      fingerprints[questionId] = contentFingerprint;
    }
    state = state.copyWith(
      isLoaded: true,
      studyQuestionAnswers: Map<String, String>.unmodifiable(answers),
      studyQuestionCorrectness: Map<String, bool>.unmodifiable(correctness),
      studyQuestionFingerprints: Map<String, String>.unmodifiable(fingerprints),
    );
    unawaited(_repository.saveStudyQuestionAnswers(answers));
    unawaited(_repository.saveStudyQuestionCorrectness(correctness));
    unawaited(_repository.saveStudyQuestionContent(
      version: state.studyQuestionContentVersion ?? '',
      fingerprints: fingerprints,
    ));
  }

  /// Keeps answers only when the exact canonical question payload is still
  /// present. A workbook revision may reuse question ids, so ids alone are not
  /// a safe compatibility signal. This intentionally affects only Study
  /// answer/score records; favourites and all other local progress stay put.
  Future<void> reconcileStudyQuestionContent({
    required String version,
    required Map<String, String> fingerprints,
  }) async {
    await _restoreFuture;
    if (!mounted || version.isEmpty) return;
    if (state.studyQuestionContentVersion == version) return;

    _changedBeforeRestore = true;
    final previousFingerprints = state.studyQuestionFingerprints;
    final answers = Map<String, String>.of(state.studyQuestionAnswers)
      ..removeWhere(
        (questionId, _) =>
            fingerprints[questionId] == null ||
            previousFingerprints[questionId] != fingerprints[questionId],
      );
    final correctness = Map<String, bool>.of(state.studyQuestionCorrectness)
      ..removeWhere(
        (questionId, _) => !answers.containsKey(questionId),
      );
    final retainedFingerprints = <String, String>{
      for (final questionId in answers.keys)
        questionId: fingerprints[questionId]!,
    };
    state = state.copyWith(
      isLoaded: true,
      studyQuestionAnswers: Map<String, String>.unmodifiable(answers),
      studyQuestionCorrectness: Map<String, bool>.unmodifiable(correctness),
      studyQuestionContentVersion: version,
      studyQuestionFingerprints:
          Map<String, String>.unmodifiable(retainedFingerprints),
    );
    await _repository.saveStudyQuestionAnswers(answers);
    await _repository.saveStudyQuestionCorrectness(correctness);
    await _repository.saveStudyQuestionContent(
      version: version,
      fingerprints: retainedFingerprints,
    );
  }

  void markStudySectionCompleted({
    required String moduleId,
    required String section,
    required int sectionCount,
  }) {
    _changedBeforeRestore = true;
    final key = '$moduleId:$section';
    final sections = Set<String>.of(state.completedStudySectionKeys)..add(key);
    final moduleSections =
        sections.where((item) => item.startsWith('$moduleId:')).length;
    final modules = Set<String>.of(state.completedStudyModuleIds);
    if (moduleSections >= sectionCount) {
      modules.add(moduleId);
    }
    state = state.copyWith(
      isLoaded: true,
      completedStudySectionKeys: Set<String>.unmodifiable(sections),
      completedStudyModuleIds: Set<String>.unmodifiable(modules),
    );
    unawaited(_repository.saveCompletedStudySectionKeys(sections));
    unawaited(_repository.saveCompletedStudyModuleIds(modules));
  }

  /// Clears only the progress data that belongs to [moduleId].
  ///
  /// Study question ids are generated with their module id as the prefix, so
  /// this also removes the module's Reading and Test answers and scores while
  /// leaving the learner's favourites and every other module untouched.
  void resetStudyModuleProgress(String moduleId) {
    _changedBeforeRestore = true;
    final sectionPrefix = '$moduleId:';
    final questionPrefix = '$moduleId-';
    final sections = Set<String>.of(state.completedStudySectionKeys)
      ..removeWhere((key) => key.startsWith(sectionPrefix));
    final modules = Set<String>.of(state.completedStudyModuleIds)
      ..remove(moduleId);
    final answers = Map<String, String>.of(state.studyQuestionAnswers)
      ..removeWhere((questionId, _) => questionId.startsWith(questionPrefix));
    final correctness = Map<String, bool>.of(state.studyQuestionCorrectness)
      ..removeWhere((questionId, _) => questionId.startsWith(questionPrefix));
    final fingerprints = Map<String, String>.of(state.studyQuestionFingerprints)
      ..removeWhere((questionId, _) => questionId.startsWith(questionPrefix));
    final isCurrentModule = state.studyLastModuleId == moduleId;

    state = state.copyWith(
      isLoaded: true,
      completedStudySectionKeys: Set<String>.unmodifiable(sections),
      completedStudyModuleIds: Set<String>.unmodifiable(modules),
      studyQuestionAnswers: Map<String, String>.unmodifiable(answers),
      studyQuestionCorrectness: Map<String, bool>.unmodifiable(correctness),
      studyQuestionFingerprints: Map<String, String>.unmodifiable(fingerprints),
      clearStudyLastModuleId: isCurrentModule,
      clearStudyLastSection: isCurrentModule,
    );
    unawaited(_repository.saveCompletedStudySectionKeys(sections));
    unawaited(_repository.saveCompletedStudyModuleIds(modules));
    unawaited(_repository.saveStudyQuestionAnswers(answers));
    unawaited(_repository.saveStudyQuestionCorrectness(correctness));
    unawaited(_repository.saveStudyQuestionContent(
      version: state.studyQuestionContentVersion ?? '',
      fingerprints: fingerprints,
    ));
    if (isCurrentModule) {
      unawaited(_repository.saveStudyLocation());
    }
  }

  void setTestLastModuleNo(int moduleNo) {
    _changedBeforeRestore = true;
    state = state.copyWith(isLoaded: true, testLastModuleNo: moduleNo);
    unawaited(_repository.saveTestLastModuleNo(moduleNo));
  }

  void markTestFlashcardKnown(String wordId) {
    _changedBeforeRestore = true;
    final ids = Set<String>.of(state.testFlashcardKnownIds)..add(wordId);
    state = state.copyWith(
      isLoaded: true,
      testFlashcardKnownIds: Set<String>.unmodifiable(ids),
    );
    unawaited(_repository.saveTestFlashcardKnownIds(ids));
  }

  void markTestMatchingCompleted(int moduleNo) {
    _changedBeforeRestore = true;
    final ids = Set<String>.of(state.completedTestMatchingModuleIds)
      ..add(moduleNo.toString());
    state = state.copyWith(
      isLoaded: true,
      completedTestMatchingModuleIds: Set<String>.unmodifiable(ids),
    );
    unawaited(_repository.saveCompletedTestMatchingModuleIds(ids));
  }

  void answerTestQuestion({
    required String questionId,
    required String answer,
    required bool isCorrect,
    String? contentFingerprint,
  }) {
    _changedBeforeRestore = true;
    final answers = Map<String, String>.of(state.testQuestionAnswers)
      ..[questionId] = answer;
    final correctness = Map<String, bool>.of(state.testQuestionCorrectness)
      ..[questionId] = isCorrect;
    final fingerprints = Map<String, String>.of(state.testQuestionFingerprints);
    if (contentFingerprint != null && contentFingerprint.isNotEmpty) {
      fingerprints[questionId] = contentFingerprint;
    }
    state = state.copyWith(
      isLoaded: true,
      testQuestionAnswers: Map<String, String>.unmodifiable(answers),
      testQuestionCorrectness: Map<String, bool>.unmodifiable(correctness),
      testQuestionFingerprints: Map<String, String>.unmodifiable(fingerprints),
    );
    unawaited(_repository.saveTestQuestionAnswers(answers));
    unawaited(_repository.saveTestQuestionCorrectness(correctness));
    unawaited(_repository.saveTestQuestionContent(
      version: state.testQuestionContentVersion ?? '',
      fingerprints: fingerprints,
    ));
  }

  /// Test Bank revisions must never attach an old response to a different
  /// canonical question. Records absent from [fingerprints] are removed before
  /// the map is dereferenced, so deleted question ids are safe too.
  Future<void> reconcileTestQuestionContent({
    required String version,
    required Map<String, String> fingerprints,
  }) async {
    await _restoreFuture;
    if (!mounted || version.isEmpty) return;
    if (state.testQuestionContentVersion == version) return;

    _changedBeforeRestore = true;
    final previousFingerprints = state.testQuestionFingerprints;
    final answers = Map<String, String>.of(state.testQuestionAnswers)
      ..removeWhere(
        (questionId, _) =>
            fingerprints[questionId] == null ||
            previousFingerprints[questionId] != fingerprints[questionId],
      );
    final correctness = Map<String, bool>.of(state.testQuestionCorrectness)
      ..removeWhere((questionId, _) => !answers.containsKey(questionId));
    final retainedFingerprints = <String, String>{
      for (final questionId in answers.keys)
        questionId: fingerprints[questionId]!,
    };
    state = state.copyWith(
      isLoaded: true,
      testQuestionAnswers: Map<String, String>.unmodifiable(answers),
      testQuestionCorrectness: Map<String, bool>.unmodifiable(correctness),
      testQuestionContentVersion: version,
      testQuestionFingerprints:
          Map<String, String>.unmodifiable(retainedFingerprints),
    );
    await _repository.saveTestQuestionAnswers(answers);
    await _repository.saveTestQuestionCorrectness(correctness);
    await _repository.saveTestQuestionContent(
      version: version,
      fingerprints: retainedFingerprints,
    );
  }

  void setTestExamLastQuestion({required int testNo, required int index}) {
    _changedBeforeRestore = true;
    final indexes = Map<String, int>.of(state.testExamLastQuestionIndexes)
      ..[testNo.toString()] = index;
    state = state.copyWith(
      isLoaded: true,
      testExamLastQuestionIndexes: Map<String, int>.unmodifiable(indexes),
    );
    unawaited(_repository.saveTestExamLastQuestionIndexes(indexes));
  }

  void setTestExamBestScore({
    required int testNo,
    required int correct,
    required int total,
  }) {
    if (total == 0) return;
    _changedBeforeRestore = true;
    final key = testNo.toString();
    final score = ((correct / total) * 100).round();
    final scores = Map<String, int>.of(state.testExamBestScores);
    if ((scores[key] ?? 0) >= score) return;
    scores[key] = score;
    state = state.copyWith(
      isLoaded: true,
      testExamBestScores: Map<String, int>.unmodifiable(scores),
    );
    unawaited(_repository.saveTestExamBestScores(scores));
  }
}
