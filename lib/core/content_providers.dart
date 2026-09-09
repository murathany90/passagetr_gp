import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/content_models.dart';
import '../models/study_models.dart';
import '../models/test_models.dart';
import '../repositories/static_content_repository.dart';
import '../repositories/static_dictionary_repository.dart';
import '../repositories/static_study_repository.dart';
import '../repositories/static_test_repository.dart';
import '../repositories/word_lookup_service.dart';
import '../features/tts/student_tts_controller.dart';
import '../features/tts/student_tts_engine.dart';
import 'local_progress.dart';

final staticContentRepositoryProvider =
    Provider<StaticContentRepository>((ref) {
  return StaticContentRepository();
});

final staticDictionaryRepositoryProvider =
    Provider<StaticDictionaryRepository>((ref) {
  return StaticDictionaryRepository();
});

final staticStudyRepositoryProvider = Provider<StaticStudyRepository>((ref) {
  return StaticStudyRepository();
});

final staticTestRepositoryProvider = Provider<StaticTestRepository>((ref) {
  return StaticTestRepository();
});

final wordLookupServiceProvider = Provider<WordLookupService>((ref) {
  return WordLookupService(
    content: ref.watch(staticContentRepositoryProvider),
    dictionary: ref.watch(staticDictionaryRepositoryProvider),
  );
});

final contentPacksProvider = FutureProvider<List<ContentPack>>((ref) {
  return ref.watch(staticContentRepositoryProvider).loadPacks();
});

final wordsProvider = FutureProvider<List<WordEntry>>((ref) {
  return ref.watch(staticContentRepositoryProvider).loadWords();
});

final readingsProvider = FutureProvider<List<ReadingPassage>>((ref) {
  return ref.watch(staticContentRepositoryProvider).loadReadings();
});

final readingDetailProvider =
    FutureProvider.family<ReadingDetail, String>((ref, id) {
  return ref.watch(staticContentRepositoryProvider).loadReading(id);
});

/// Applies the one-time legacy (001–678) reading-progress migration before a
/// reading screen shows completion state. New source-number IDs are added;
/// nothing else in local progress is touched.
final readingProgressMigrationProvider = FutureProvider<void>((ref) async {
  final mapping =
      await ref.watch(staticContentRepositoryProvider).loadLegacyReadingIdMap();
  await ref
      .read(localProgressProvider.notifier)
      .migrateLegacyReadingIds(mapping);
});

final studyModulesProvider = FutureProvider<List<StudyModuleSummary>>((ref) {
  return ref.watch(staticStudyRepositoryProvider).loadModules();
});

final studyModuleDetailProvider =
    FutureProvider.family<StudyModuleDetail, String>((ref, id) {
  return ref.watch(staticStudyRepositoryProvider).loadModule(id);
});

/// Reconciles persisted Study answers before a Study screen can show them.
/// Only question records whose canonical payload fingerprint changed are
/// removed; favourites and all unrelated local state remain untouched.
final studyQuestionCompatibilityProvider = FutureProvider<void>((ref) async {
  final contract = await ref
      .watch(staticStudyRepositoryProvider)
      .loadQuestionContentContract();
  await ref.read(localProgressProvider.notifier).reconcileStudyQuestionContent(
        version: contract.version,
        fingerprints: contract.fingerprints,
      );
});

final testBankManifestProvider = FutureProvider<TestBankManifest>((ref) {
  return ref.watch(staticTestRepositoryProvider).loadManifest();
});

final testModulesProvider = FutureProvider<List<TestModuleSummary>>((ref) {
  return ref.watch(staticTestRepositoryProvider).loadModules();
});

final testModuleDetailProvider =
    FutureProvider.family<TestModuleDetail, int>((ref, moduleNo) {
  return ref.watch(staticTestRepositoryProvider).loadModule(moduleNo);
});

/// Test Bank favourites always resolve from Testler JSON assets, never from
/// the main Words repository or `favoriteWordIds`.
final testFavoriteWordsProvider = FutureProvider<List<TestBankWord>>((ref) {
  final ids = ref.watch(localProgressProvider).testFavoriteWordIds;
  return ref.watch(staticTestRepositoryProvider).loadWordsByIds(ids);
});

final testStructuresProvider = FutureProvider<TestStructureBank>((ref) {
  return ref.watch(staticTestRepositoryProvider).loadStructures();
});

final testExamsProvider = FutureProvider<List<TestExamSummary>>((ref) {
  return ref.watch(staticTestRepositoryProvider).loadExams();
});

final testExamProvider = FutureProvider.family<TestExam, int>((ref, testNo) {
  return ref.watch(staticTestRepositoryProvider).loadExam(testNo);
});

/// Test Bank revisions only remove incompatible Test answer records. Favourites,
/// Study progress and unrelated local state are intentionally preserved.
final testQuestionCompatibilityProvider = FutureProvider<void>((ref) async {
  final contract = await ref
      .watch(staticTestRepositoryProvider)
      .loadQuestionContentContract();
  await ref.read(localProgressProvider.notifier).reconcileTestQuestionContent(
        version: contract.version,
        fingerprints: contract.fingerprints,
      );
});

final studentTtsEngineProvider = Provider<StudentTtsEngine>((ref) {
  final engine = NativeStudentTtsEngine();
  ref.onDispose(engine.dispose);
  return engine;
});

final studentTtsControllerProvider =
    StateNotifierProvider<StudentTtsController, StudentTtsState>((ref) {
  return StudentTtsController(engine: ref.watch(studentTtsEngineProvider));
});
