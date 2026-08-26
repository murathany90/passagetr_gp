import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/app_theme.dart';
import '../features/common/page_parts.dart';
import '../features/home/landing_page.dart';
import '../features/readings/reading_detail_page.dart';
import '../features/readings/readings_page.dart';
import '../features/words/flashcards_page.dart';
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
                path: '/words', builder: (context, state) => const WordsPage()),
            GoRoute(
              path: '/words/flashcards',
              builder: (context, state) =>
                  FlashcardsPage(packId: state.uri.queryParameters['packId']),
            ),
            GoRoute(
              path: '/words/mini-test',
              builder: (context, state) =>
                  MiniTestPage(packId: state.uri.queryParameters['packId']),
            ),
            GoRoute(
                path: '/readings',
                builder: (context, state) => const ReadingsPage()),
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

class PassagetrApp extends ConsumerWidget {
  const PassagetrApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
        title: 'PASSAGETR',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        routerConfig: ref.watch(_routerProvider),
      );
}
