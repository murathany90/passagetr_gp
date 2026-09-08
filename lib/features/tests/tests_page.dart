import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme_tokens.dart';
import '../../core/content_providers.dart';
import '../../core/local_progress.dart';
import '../../models/test_models.dart';
import '../../repositories/local_progress_repository.dart';
import '../common/page_parts.dart';

class TestsPage extends ConsumerStatefulWidget {
  const TestsPage({super.key});

  @override
  ConsumerState<TestsPage> createState() => _TestsPageState();
}

class _TestsPageState extends ConsumerState<TestsPage> {
  static const _pageSize = 10;
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final compatibility = ref.watch(testQuestionCompatibilityProvider);
    if (compatibility.isLoading) {
      return const PageFrame(
        title: 'Testler',
        subtitle: 'Test ilerlemesi doğrulanıyor.',
        child: Center(
            child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        )),
      );
    }
    if (compatibility.hasError) {
      return DataLoadErrorPage(
        message: compatibility.error.toString(),
        onRetry: () => ref.invalidate(testQuestionCompatibilityProvider),
      );
    }

    final manifest = ref.watch(testBankManifestProvider);
    final modules = ref.watch(testModulesProvider);
    return manifest.when(
      loading: _loading,
      error: _error,
      data: (bank) => modules.when(
        loading: _loading,
        error: _error,
        data: (allModules) => _content(context, bank, allModules),
      ),
    );
  }

  Widget _loading() => const PageFrame(
        title: 'Testler',
        subtitle: 'İçerik hazırlanıyor.',
        child: Center(
            child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        )),
      );

  Widget _error(Object error, StackTrace _) => DataLoadErrorPage(
        message: error.toString(),
        onRetry: () {
          ref.invalidate(testBankManifestProvider);
          ref.invalidate(testModulesProvider);
        },
      );

  Widget _content(
    BuildContext context,
    TestBankManifest bank,
    List<TestModuleSummary> modules,
  ) {
    final totalPages = (modules.length / _pageSize).ceil();
    final page = totalPages == 0 ? 0 : _page.clamp(0, totalPages - 1).toInt();
    final visible = modules.skip(page * _pageSize).take(_pageSize).toList();
    final progress = ref.watch(localProgressProvider);
    final completedExams = bank.exams
        .where((exam) =>
            _answeredExamQuestions(progress, exam.testNo) >= exam.questionCount)
        .length;
    final canonicalFavoriteCount = progress.favoriteWordIds
        .where((id) => !id.startsWith('study-word:'))
        .length;
    return PageFrame(
      title: 'Testler',
      subtitle: 'Test Bank içeriğiyle modül, yapı ve özgün test çalışması.',
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SummaryCard(
              counts: bank.counts,
              knownCards: progress.testFlashcardKnownIds.length,
              completedExams: completedExams,
            ),
            const SizedBox(height: 16),
            LayoutBuilder(builder: (context, constraints) {
              final twoColumns = constraints.maxWidth >= 640;
              final width = twoColumns
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(spacing: 12, runSpacing: 12, children: <Widget>[
                SizedBox(
                  width: width,
                  child: _FeatureCard(
                    icon: Icons.account_tree_outlined,
                    title: 'Yapılar',
                    description:
                        '${bank.counts.structures} yapı · ${bank.counts.structureCategories} kategori',
                    onTap: () => context.go('/tests/structures'),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _FeatureCard(
                    icon: Icons.quiz_outlined,
                    title: 'Özgün Testler',
                    description:
                        '$completedExams / ${bank.counts.exams} tamamlandı · ${bank.counts.questions} soru',
                    onTap: () => context.go('/tests/exams'),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _FeatureCard(
                    icon: Icons.favorite_outline_rounded,
                    title: 'Favoriler',
                    description:
                        '$canonicalFavoriteCount canonical kelime · Liste ve flash kart',
                    onTap: () => context.go('/tests/favorites'),
                  ),
                ),
              ]);
            }),
            const SizedBox(height: 22),
            Text('Modüller', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            _Pagination(
              currentPage: page,
              totalPages: totalPages,
              totalItems: modules.length,
              onChanged: (next) => setState(() => _page = next),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, constraints) {
              final columns = constraints.maxWidth >= 760 ? 2 : 1;
              final width = columns == 2
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: visible
                    .map((module) => SizedBox(
                          width: width,
                          child: _ModuleCard(
                            module: module,
                            active:
                                progress.testLastModuleNo == module.moduleNo,
                            known: progress.testFlashcardKnownIds
                                .where((id) => id.startsWith('${module.id}:'))
                                .length,
                            matchingDone: progress
                                .completedTestMatchingModuleIds
                                .contains(module.moduleNo.toString()),
                          ),
                        ))
                    .toList(growable: false),
              );
            }),
          ]),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.counts,
    required this.knownCards,
    required this.completedExams,
  });
  final TestBankCounts counts;
  final int knownCards;
  final int completedExams;

  @override
  Widget build(BuildContext context) {
    final items = <(String, String)>[
      ('Modül', '${counts.modules}'),
      ('Kelime kaydı', '${counts.wordRows}'),
      ('Kart ilerleme', '$knownCards / ${counts.wordRows}'),
      ('Yapı', '${counts.structures}'),
      ('Özgün test', '$completedExams / ${counts.exams}'),
      ('Soru', '${counts.questions}'),
    ];
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth >= 860
            ? (constraints.maxWidth - 48) / items.length
            : (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 12,
          children: items
              .map((item) => SizedBox(
                    width: width,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(item.$2,
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 2),
                          Text(item.$1,
                              style: Theme.of(context).textTheme.bodySmall),
                        ]),
                  ))
              .toList(growable: false),
        );
      }),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(children: <Widget>[
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: tokens.accentSoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: tokens.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 3),
              Text(description, style: Theme.of(context).textTheme.bodySmall),
            ])),
        const Icon(Icons.chevron_right_rounded),
      ]),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.module,
    required this.active,
    required this.known,
    required this.matchingDone,
  });
  final TestModuleSummary module;
  final bool active;
  final int known;
  final bool matchingDone;

  @override
  Widget build(BuildContext context) {
    final completedItems =
        known.clamp(0, module.wordCount).toInt() + (matchingDone ? 1 : 0);
    final totalItems = module.wordCount + 1;
    return SurfaceCard(
      onTap: () => context.go('/tests/module/${module.moduleNo}'),
      padding: const EdgeInsets.all(16),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(children: <Widget>[
              Text('Modül ${module.moduleNo}',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              if (active) const Icon(Icons.play_circle_fill_rounded, size: 19),
            ]),
            const SizedBox(height: 6),
            Text('${module.wordCount} kelime',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: completedItems / totalItems),
            const SizedBox(height: 7),
            Text(
              matchingDone
                  ? '$completedItems / $totalItems adım · Eşleştirme tamamlandı'
                  : '$completedItems / $totalItems adım · $known kart bilindi',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: () => context.go('/tests/module/${module.moduleNo}'),
                child: Text(active ? 'Devam et' : 'Aç'),
              ),
            ),
          ]),
    );
  }
}

int _answeredExamQuestions(LocalProgressSnapshot progress, int testNo) {
  final prefix = 'test-${testNo.toString().padLeft(2, '0')}-q-';
  return progress.testQuestionAnswers.keys
      .where((questionId) => questionId.startsWith(prefix))
      .length;
}

class _Pagination extends StatelessWidget {
  const _Pagination({
    required this.currentPage,
    required this.totalPages,
    required this.totalItems,
    required this.onChanged,
  });
  final int currentPage;
  final int totalPages;
  final int totalItems;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: List<Widget>.generate(totalPages, (index) {
            final from = index * 10 + 1;
            final to = ((index + 1) * 10).clamp(0, totalItems);
            return ChoiceChip(
              label: Text('$from–$to'),
              selected: currentPage == index,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => onChanged(index),
            );
          }),
        ),
      );
}
