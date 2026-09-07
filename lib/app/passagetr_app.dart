import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/app_theme.dart';
import '../core/theme_mode_controller.dart';
import '../features/common/page_parts.dart';
import '../features/dictionary/dictionary_page.dart';
import '../features/home/landing_page.dart';
import '../features/readings/reading_detail_page.dart';
import '../features/readings/readings_page.dart';
import '../features/study/study_module_page.dart';
import '../features/study/study_page.dart';
import '../features/tests/test_exams_page.dart';
import '../features/tests/test_module_page.dart';
import '../features/tests/test_structures_page.dart';
import '../features/tests/tests_page.dart';
import '../features/words/flashcards_page.dart';
import '../features/words/find_word_page.dart';
import '../features/words/matching_page.dart';
import '../features/words/mini_test_page.dart';
import '../features/words/words_page.dart';

final _routerProvider = Provider<GoRouter>((ref) => GoRouter(
      routes: <RouteBase>[
        ShellRoute(
          builder: (context, state, child) =>
              PassagetrShell(location: state.uri.path, child: child),
          routes: <RouteBase>[
            GoRoute(
                path: '/', builder: (context, state) => const LandingPage()),
            GoRoute(
              path: '/words',
              builder: (context, state) => WordsPage(
                initialQuery: state.uri.queryParameters['q'],
              ),
            ),
            GoRoute(
              path: '/dictionary',
              builder: (context, state) => DictionaryPage(
                initialQuery: state.uri.queryParameters['q'],
              ),
            ),
            GoRoute(
              path: '/words/flashcards',
              builder: (context, state) => const FlashcardsPage(),
            ),
            GoRoute(
              path: '/words/mini-test',
              builder: (context, state) => const MiniTestPage(),
            ),
            GoRoute(
              path: '/words/matching',
              builder: (context, state) => const MatchingPage(),
            ),
            GoRoute(
              path: '/words/find-word',
              builder: (context, state) => const FindWordPage(),
            ),
            GoRoute(
                path: '/readings',
                builder: (context, state) => const ReadingsPage()),
            GoRoute(
                path: '/study', builder: (context, state) => const StudyPage()),
            GoRoute(
              path: '/study/module/:moduleId',
              builder: (context, state) => StudyModulePage(
                moduleId: state.pathParameters['moduleId']!,
              ),
            ),
            GoRoute(
              path: '/tests',
              builder: (context, state) => const TestsPage(),
            ),
            GoRoute(
              path: '/tests/module/:moduleNo',
              builder: (context, state) {
                final moduleNo =
                    _parseModuleNo(state.pathParameters['moduleNo']);
                if (moduleNo == null) {
                  return const DataLoadErrorPage(
                      message: 'Sayfa bulunamadı.');
                }
                return TestModulePage(moduleNo: moduleNo);
              },
            ),
            GoRoute(
              path: '/tests/module/:moduleNo/flashcards',
              builder: (context, state) {
                final moduleNo =
                    _parseModuleNo(state.pathParameters['moduleNo']);
                if (moduleNo == null) {
                  return const DataLoadErrorPage(
                      message: 'Sayfa bulunamadı.');
                }
                return TestFlashcardsPage(moduleNo: moduleNo);
              },
            ),
            GoRoute(
              path: '/tests/module/:moduleNo/matching',
              builder: (context, state) {
                final moduleNo =
                    _parseModuleNo(state.pathParameters['moduleNo']);
                if (moduleNo == null) {
                  return const DataLoadErrorPage(
                      message: 'Sayfa bulunamadı.');
                }
                return TestMatchingPage(moduleNo: moduleNo);
              },
            ),
            GoRoute(
              path: '/tests/structures',
              builder: (context, state) => const TestStructuresPage(),
            ),
            GoRoute(
              path: '/tests/exams',
              builder: (context, state) => const TestExamsPage(),
            ),
            GoRoute(
              path: '/tests/exam/:testNo',
              builder: (context, state) {
                final testNo = _parseTestNo(state.pathParameters['testNo']);
                if (testNo == null) {
                  return const DataLoadErrorPage(
                      message: 'Sayfa bulunamadı.');
                }
                return TestExamPage(testNo: testNo);
              },
            ),
            GoRoute(
              path: '/tests/wrong',
              builder: (context, state) => const TestWrongAnswersPage(),
            ),
            GoRoute(
              path: '/readings/:id',
              builder: (context, state) =>
                  ReadingDetailPage(readingId: state.pathParameters['id']!),
            ),
          ],
        ),
      ],
      errorBuilder: (context, state) =>
          const DataLoadErrorPage(message: 'Sayfa bulunamadı.'),
    ));

/// Geçersiz sayısal route parametreleri crash yerine "Sayfa bulunamadı"
/// durumuna düşer. Modüller 1–110, özgün testler 1–9 aralığındadır.
int? _parseModuleNo(String? raw) => _parseBounded(raw, min: 1, max: 110);

int? _parseTestNo(String? raw) => _parseBounded(raw, min: 1, max: 9);

int? _parseBounded(String? raw, {required int min, required int max}) {
  final parsed = int.tryParse((raw ?? '').trim());
  if (parsed == null || parsed < min || parsed > max) return null;
  return parsed;
}

class PassagetrApp extends ConsumerWidget {
  const PassagetrApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
        title: 'PASSAGETR',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ref.watch(themeModeProvider),
        routerConfig: ref.watch(_routerProvider),
      );
}
