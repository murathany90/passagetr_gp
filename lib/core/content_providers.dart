import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/content_models.dart';
import '../repositories/static_content_repository.dart';
import '../repositories/static_dictionary_repository.dart';
import '../repositories/word_lookup_service.dart';
import '../features/tts/student_tts_controller.dart';
import '../features/tts/student_tts_engine.dart';

final staticContentRepositoryProvider =
    Provider<StaticContentRepository>((ref) {
  return StaticContentRepository();
});

final staticDictionaryRepositoryProvider =
    Provider<StaticDictionaryRepository>((ref) {
  return StaticDictionaryRepository();
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

final studentTtsEngineProvider = Provider<StudentTtsEngine>((ref) {
  final engine = NativeStudentTtsEngine();
  ref.onDispose(engine.dispose);
  return engine;
});

final studentTtsControllerProvider =
    StateNotifierProvider<StudentTtsController, StudentTtsState>((ref) {
  return StudentTtsController(engine: ref.watch(studentTtsEngineProvider));
});
