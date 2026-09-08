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
  bool _restoreDone = false;
  final Set<String> _dirtyKeys = <String>{};

  void _markDirty(String key) => _dirtyKeys.add(key);

  Future<void> get restoreFuture => _restoreFuture;
  bool get restoreDone => _restoreDone;

  /// Restore bitmeden storage'a yazmak, henüz yüklenmemiş kayıtların
  /// üzerine kısmi state yazıp veri kaybına yol açar. Bu yüzden restore
  /// tamamlanmadan gelen yazmalar atlanır; restore birleştirilmiş state'i
  /// kendisi persist eder.
  void _save(Future<void> Function() write) {
    if (_restoreDone) {
      unawaited(write());
    }
  }

  Future<void> _persistMerged(LocalProgressSnapshot merged) async {
    if (_dirtyKeys.contains('wordFilters')) {
      await _repository.saveWordFilters(
          tag: merged.wordTag, level: merged.wordLevel);
    }
    if (_dirtyKeys.contains('readingFilters')) {
      await _repository.saveReadingFilters(
          level: merged.readingLevel, category: merged.readingCategory);
    }
    if (_dirtyKeys.contains('favWords')) {
      await _repository.saveFavoriteWordIds(merged.favoriteWordIds);
    }
    if (_dirtyKeys.contains('knownWords')) {
      await _repository.saveKnownWordIds(merged.knownWordIds);
    }
    if (_dirtyKeys.contains('completedReadings')) {
      await _repository.saveCompletedReadingIds(merged.completedReadingIds);
    }
    if (_dirtyKeys.contains('studyLocation')) {
      await _repository.saveStudyLocation(
          moduleId: merged.studyLastModuleId, section: merged.studyLastSection);
    }
    if (_dirtyKeys.contains('studyAnswers')) {
      await _repository.saveStudyQuestionAnswers(merged.studyQuestionAnswers);
      await _repository
          .saveStudyQuestionCorrectness(merged.studyQuestionCorrectness);
      await _repository.saveStudyQuestionContent(
        version: merged.studyQuestionContentVersion ?? '',
        fingerprints: merged.studyQuestionFingerprints,
      );
    }
    if (_dirtyKeys.contains('studySections')) {
      await _repository
          .saveCompletedStudySectionKeys(merged.completedStudySectionKeys);
      await _repository
          .saveCompletedStudyModuleIds(merged.completedStudyModuleIds);
    }
    if (_dirtyKeys.contains('testLastModule')) {
      await _repository.saveTestLastModuleNo(merged.testLastModuleNo);
    }
    if (_dirtyKeys.contains('testFlashcards')) {
      await _repository.saveTestFlashcardKnownIds(merged.testFlashcardKnownIds);
    }
    if (_dirtyKeys.contains('testMatching')) {
      await _repository.saveCompletedTestMatchingModuleIds(
          merged.completedTestMatchingModuleIds);
    }
    if (_dirtyKeys.contains('testAnswers')) {
      await _repository.saveTestQuestionAnswers(merged.testQuestionAnswers);
      await _repository
          .saveTestQuestionCorrectness(merged.testQuestionCorrectness);
      await _repository.saveTestQuestionContent(
        version: merged.testQuestionContentVersion ?? '',
        fingerprints: merged.testQuestionFingerprints,
      );
    }
    if (_dirtyKeys.contains('examProgress')) {
      await _repository
          .saveTestExamLastQuestionIndexes(merged.testExamLastQuestionIndexes);
      await _repository.saveTestExamBestScores(merged.testExamBestScores);
    }
  }

  Future<void> _restore() async {
    try {
      final restored = await _repository.load();
      if (!mounted) return;
      if (_dirtyKeys.isEmpty) {
        state = restored.copyWith(isLoaded: true);
      } else {
        // Restore tamamlanmadan yapılan kullanıcı değişiklikleri korunur:
        // set/map alanlar birleştirilir (çakışmada yeni değer kazanır),
        // scalar alanlarda dokunulan değer korunur.
        final current = state;
        state = restored.copyWith(
          isLoaded: true,
          favoriteWordIds: _dirtyKeys.contains('favWords')
              ? <String>{...restored.favoriteWordIds, ...current.favoriteWordIds}
              : restored.favoriteWordIds,
          knownWordIds: _dirtyKeys.contains('knownWords')
              ? <String>{...restored.knownWordIds, ...current.knownWordIds}
              : restored.knownWordIds,
          completedReadingIds: _dirtyKeys.contains('completedReadings')
              ? <String>{
                  ...restored.completedReadingIds,
                  ...current.completedReadingIds
                }
              : restored.completedReadingIds,
          wordTag: _dirtyKeys.contains('wordFilters')
              ? current.wordTag
              : restored.wordTag,
          wordLevel: _dirtyKeys.contains('wordFilters')
              ? current.wordLevel
              : restored.wordLevel,
          readingLevel: _dirtyKeys.contains('readingFilters')
              ? current.readingLevel
              : restored.readingLevel,
          readingCategory: _dirtyKeys.contains('readingFilters')
              ? current.readingCategory
              : restored.readingCategory,
          completedStudyModuleIds: _dirtyKeys.contains('studySections')
              ? <String>{
                  ...restored.completedStudyModuleIds,
                  ...current.completedStudyModuleIds
                }
              : restored.completedStudyModuleIds,
          completedStudySectionKeys: _dirtyKeys.contains('studySections')
              ? <String>{
                  ...restored.completedStudySectionKeys,
                  ...current.completedStudySectionKeys
                }
              : restored.completedStudySectionKeys,
          studyLastModuleId: _dirtyKeys.contains('studyLocation')
              ? current.studyLastModuleId
              : restored.studyLastModuleId,
          studyLastSection: _dirtyKeys.contains('studyLocation')
              ? current.studyLastSection
              : restored.studyLastSection,
          studyQuestionAnswers: _dirtyKeys.contains('studyAnswers')
              ? <String, String>{
                  ...restored.studyQuestionAnswers,
                  ...current.studyQuestionAnswers
                }
              : restored.studyQuestionAnswers,
          studyQuestionCorrectness: _dirtyKeys.contains('studyAnswers')
              ? <String, bool>{
                  ...restored.studyQuestionCorrectness,
                  ...current.studyQuestionCorrectness
                }
              : restored.studyQuestionCorrectness,
          studyQuestionContentVersion: _dirtyKeys.contains('studyAnswers')
              ? current.studyQuestionContentVersion
              : restored.studyQuestionContentVersion,
          studyQuestionFingerprints: _dirtyKeys.contains('studyAnswers')
              ? <String, String>{
                  ...restored.studyQuestionFingerprints,
                  ...current.studyQuestionFingerprints
                }
              : restored.studyQuestionFingerprints,
          testLastModuleNo: _dirtyKeys.contains('testLastModule')
              ? current.testLastModuleNo
              : restored.testLastModuleNo,
          testFlashcardKnownIds: _dirtyKeys.contains('testFlashcards')
              ? <String>{
                  ...restored.testFlashcardKnownIds,
                  ...current.testFlashcardKnownIds
                }
              : restored.testFlashcardKnownIds,
          completedTestMatchingModuleIds: _dirtyKeys.contains('testMatching')
              ? <String>{
                  ...restored.completedTestMatchingModuleIds,
                  ...current.completedTestMatchingModuleIds
                }
              : restored.completedTestMatchingModuleIds,
          testQuestionAnswers: _dirtyKeys.contains('testAnswers')
              ? <String, String>{
                  ...restored.testQuestionAnswers,
                  ...current.testQuestionAnswers
                }
              : restored.testQuestionAnswers,
          testQuestionCorrectness: _dirtyKeys.contains('testAnswers')
              ? <String, bool>{
                  ...restored.testQuestionCorrectness,
                  ...current.testQuestionCorrectness
                }
              : restored.testQuestionCorrectness,
          testQuestionContentVersion: _dirtyKeys.contains('testAnswers')
              ? current.testQuestionContentVersion
              : restored.testQuestionContentVersion,
          testQuestionFingerprints: _dirtyKeys.contains('testAnswers')
              ? <String, String>{
                  ...restored.testQuestionFingerprints,
                  ...current.testQuestionFingerprints
                }
              : restored.testQuestionFingerprints,
          testExamLastQuestionIndexes: _dirtyKeys.contains('examProgress')
              ? <String, int>{
                  ...restored.testExamLastQuestionIndexes,
                  ...current.testExamLastQuestionIndexes
                }
              : restored.testExamLastQuestionIndexes,
          testExamBestScores: _dirtyKeys.contains('examProgress')
              ? <String, int>{
                  ...restored.testExamBestScores,
                  ...current.testExamBestScores
                }
              : restored.testExamBestScores,
        );
        await _persistMerged(state);
      }
    } catch (_) {
      if (mounted) {
        state = state.copyWith(isLoaded: true);
      }
    } finally {
      _restoreDone = true;
    }
  }

  void setWordFilters({String? tag, String? level}) {
    _markDirty('wordFilters');
    state = state.copyWith(
      isLoaded: true,
      wordTag: tag,
      clearWordTag: tag == null,
      wordLevel: level,
      clearWordLevel: level == null,
    );
    _save(() => _repository.saveWordFilters(tag: tag, level: level));
  }

  void setReadingFilters({String? level, String? category}) {
    _markDirty('readingFilters');
    state = state.copyWith(
      isLoaded: true,
      readingLevel: level,
      clearReadingLevel: level == null,
      readingCategory: category,
      clearReadingCategory: category == null,
    );
    _save(() => _repository.saveReadingFilters(level: level, category: category));
  }

  void toggleFavoriteWord(String wordId) {
    _markDirty('favWords');
    final ids = Set<String>.of(state.favoriteWordIds);
    ids.contains(wordId) ? ids.remove(wordId) : ids.add(wordId);
    state =
        state.copyWith(isLoaded: true, favoriteWordIds: Set.unmodifiable(ids));
    _save(() => _repository.saveFavoriteWordIds(ids));
  }

  void markWordKnown(String wordId) {
    if (state.knownWordIds.contains(wordId)) {
      return;
    }
    _markDirty('knownWords');
    final ids = Set<String>.of(state.knownWordIds)..add(wordId);
    state = state.copyWith(isLoaded: true, knownWordIds: Set.unmodifiable(ids));
    _save(() => _repository.saveKnownWordIds(ids));
  }

  void toggleReadingCompleted(String readingId) {
    _markDirty('completedReadings');
    final ids = Set<String>.of(state.completedReadingIds);
    ids.contains(readingId) ? ids.remove(readingId) : ids.add(readingId);
    state = state.copyWith(
        isLoaded: true, completedReadingIds: Set.unmodifiable(ids));
    _save(() => _repository.saveCompletedReadingIds(ids));
  }

  void setStudyLocation({required String moduleId, required String section}) {
    _markDirty('studyLocation');
    state = state.copyWith(
      isLoaded: true,
      studyLastModuleId: moduleId,
      studyLastSection: section,
    );
    _save(() => _repository.saveStudyLocation(
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
    _markDirty('studyAnswers');
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
    _save(() => _repository.saveStudyQuestionAnswers(answers));
    _save(() => _repository.saveStudyQuestionCorrectness(correctness));
    _save(() => _repository.saveStudyQuestionContent(
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

    _markDirty('studyAnswers');
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
    _markDirty('studySections');
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
    _save(() => _repository.saveCompletedStudySectionKeys(sections));
    _save(() => _repository.saveCompletedStudyModuleIds(modules));
  }

  /// Clears only the progress data that belongs to [moduleId].
  ///
  /// Study question ids are generated with their module id as the prefix, so
  /// this also removes the module's Reading and Test answers and scores while
  /// leaving the learner's favourites and every other module untouched.
  void resetStudyModuleProgress(String moduleId) {
    _markDirty('studySections');
    _markDirty('studyAnswers');
    _markDirty('studyLocation');
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
    _save(() => _repository.saveCompletedStudySectionKeys(sections));
    _save(() => _repository.saveCompletedStudyModuleIds(modules));
    _save(() => _repository.saveStudyQuestionAnswers(answers));
    _save(() => _repository.saveStudyQuestionCorrectness(correctness));
    _save(() => _repository.saveStudyQuestionContent(
      version: state.studyQuestionContentVersion ?? '',
      fingerprints: fingerprints,
    ));
    if (isCurrentModule) {
      _save(() => _repository.saveStudyLocation());
    }
  }

  void setTestLastModuleNo(int moduleNo) {
    _markDirty('testLastModule');
    state = state.copyWith(isLoaded: true, testLastModuleNo: moduleNo);
    _save(() => _repository.saveTestLastModuleNo(moduleNo));
  }

  void markTestFlashcardKnown(String wordId) {
    _markDirty('testFlashcards');
    final ids = Set<String>.of(state.testFlashcardKnownIds)..add(wordId);
    state = state.copyWith(
      isLoaded: true,
      testFlashcardKnownIds: Set<String>.unmodifiable(ids),
    );
    _save(() => _repository.saveTestFlashcardKnownIds(ids));
  }

  void markTestMatchingCompleted(int moduleNo) {
    _markDirty('testMatching');
    final ids = Set<String>.of(state.completedTestMatchingModuleIds)
      ..add(moduleNo.toString());
    state = state.copyWith(
      isLoaded: true,
      completedTestMatchingModuleIds: Set<String>.unmodifiable(ids),
    );
    _save(() => _repository.saveCompletedTestMatchingModuleIds(ids));
  }

  /// Clears only the local learning state for one Testler module. Canonical
  /// content, favourites and every other module remain intact.
  void resetTestModuleProgress({
    required int moduleNo,
    required Iterable<String> wordIds,
  }) {
    _markDirty('testFlashcards');
    _markDirty('testMatching');
    final known = Set<String>.of(state.testFlashcardKnownIds)
      ..removeAll(wordIds);
    final matching = Set<String>.of(state.completedTestMatchingModuleIds)
      ..remove(moduleNo.toString());
    final isCurrentModule = state.testLastModuleNo == moduleNo;
    if (isCurrentModule) {
      _markDirty('testLastModule');
    }
    state = state.copyWith(
      isLoaded: true,
      testFlashcardKnownIds: Set<String>.unmodifiable(known),
      completedTestMatchingModuleIds: Set<String>.unmodifiable(matching),
      clearTestLastModuleNo: isCurrentModule,
    );
    _save(() => _repository.saveTestFlashcardKnownIds(known));
    _save(() => _repository.saveCompletedTestMatchingModuleIds(matching));
    if (isCurrentModule) {
      _save(() => _repository.saveTestLastModuleNo(null));
    }
  }

  void answerTestQuestion({
    required String questionId,
    required String answer,
    required bool isCorrect,
    String? contentFingerprint,
  }) {
    _markDirty('testAnswers');
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
    _save(() => _repository.saveTestQuestionAnswers(answers));
    _save(() => _repository.saveTestQuestionCorrectness(correctness));
    _save(() => _repository.saveTestQuestionContent(
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

    _markDirty('testAnswers');
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

  /// One-time 001–678 legacy passage-ID migration: completed readings stored
  /// under old title-derived IDs are additionally recorded under the new
  /// source-number IDs. Idempotent; legacy IDs are retained harmlessly.
  Future<void> migrateLegacyReadingIds(Map<String, String> mapping) async {
    await _restoreFuture;
    if (!mounted || mapping.isEmpty) return;
    final legacy = state.completedReadingIds
        .where(mapping.containsKey)
        .toList(growable: false);
    if (legacy.isEmpty) return;
    _markDirty('completedReadings');
    final ids = Set<String>.of(state.completedReadingIds);
    for (final oldId in legacy) {
      ids.add(mapping[oldId]!);
    }
    state = state.copyWith(
      isLoaded: true,
      completedReadingIds: Set.unmodifiable(ids),
    );
    _save(() => _repository.saveCompletedReadingIds(ids));
  }

  void setTestExamLastQuestion({required int testNo, required int index}) {
    _markDirty('examProgress');
    final indexes = Map<String, int>.of(state.testExamLastQuestionIndexes)
      ..[testNo.toString()] = index;
    state = state.copyWith(
      isLoaded: true,
      testExamLastQuestionIndexes: Map<String, int>.unmodifiable(indexes),
    );
    _save(() => _repository.saveTestExamLastQuestionIndexes(indexes));
  }

  void setTestExamBestScore({
    required int testNo,
    required int correct,
    required int total,
  }) {
    if (total == 0) return;
    _markDirty('examProgress');
    final key = testNo.toString();
    final score = ((correct / total) * 100).round();
    final scores = Map<String, int>.of(state.testExamBestScores);
    if ((scores[key] ?? 0) >= score) return;
    scores[key] = score;
    state = state.copyWith(
      isLoaded: true,
      testExamBestScores: Map<String, int>.unmodifiable(scores),
    );
    _save(() => _repository.saveTestExamBestScores(scores));
  }

  /// Removes answers, score and resume position for one original Test Bank
  /// exam. Other exams, module progress and favourites are not affected.
  void resetTestExamProgress({
    required int testNo,
    required Iterable<String> questionIds,
  }) {
    _markDirty('testAnswers');
    _markDirty('examProgress');
    final ids = questionIds.toSet();
    final answers = Map<String, String>.of(state.testQuestionAnswers)
      ..removeWhere((questionId, _) => ids.contains(questionId));
    final correctness = Map<String, bool>.of(state.testQuestionCorrectness)
      ..removeWhere((questionId, _) => ids.contains(questionId));
    final fingerprints = Map<String, String>.of(state.testQuestionFingerprints)
      ..removeWhere((questionId, _) => ids.contains(questionId));
    final key = testNo.toString();
    final indexes = Map<String, int>.of(state.testExamLastQuestionIndexes)
      ..remove(key);
    final scores = Map<String, int>.of(state.testExamBestScores)..remove(key);
    state = state.copyWith(
      isLoaded: true,
      testQuestionAnswers: Map<String, String>.unmodifiable(answers),
      testQuestionCorrectness: Map<String, bool>.unmodifiable(correctness),
      testQuestionFingerprints: Map<String, String>.unmodifiable(fingerprints),
      testExamLastQuestionIndexes: Map<String, int>.unmodifiable(indexes),
      testExamBestScores: Map<String, int>.unmodifiable(scores),
    );
    _save(() => _repository.saveTestQuestionAnswers(answers));
    _save(() => _repository.saveTestQuestionCorrectness(correctness));
    _save(() => _repository.saveTestQuestionContent(
          version: state.testQuestionContentVersion ?? '',
          fingerprints: fingerprints,
        ));
    _save(() => _repository.saveTestExamLastQuestionIndexes(indexes));
    _save(() => _repository.saveTestExamBestScores(scores));
  }
}
