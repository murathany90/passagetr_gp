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
    unawaited(_restore());
  }

  final LocalProgressRepository _repository;
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

  void answerStudyQuestion(
      {required String questionId, required String answer}) {
    _changedBeforeRestore = true;
    final answers = Map<String, String>.of(state.studyQuestionAnswers)
      ..[questionId] = answer;
    state = state.copyWith(
      isLoaded: true,
      studyQuestionAnswers: Map<String, String>.unmodifiable(answers),
    );
    unawaited(_repository.saveStudyQuestionAnswers(answers));
  }

  void markStudyModuleCompleted(String moduleId) {
    if (state.completedStudyModuleIds.contains(moduleId)) return;
    _changedBeforeRestore = true;
    final ids = Set<String>.of(state.completedStudyModuleIds)..add(moduleId);
    state = state.copyWith(
      isLoaded: true,
      completedStudyModuleIds: Set<String>.unmodifiable(ids),
    );
    unawaited(_repository.saveCompletedStudyModuleIds(ids));
  }
}
