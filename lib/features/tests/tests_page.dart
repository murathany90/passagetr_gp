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
  _ModuleFilter _filter = _ModuleFilter.all;

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
    final progress = ref.watch(localProgressProvider);
    final filteredModules = modules.where((module) {
      final state = _moduleState(module, progress);
      return switch (_filter) {
        _ModuleFilter.all => true,
        _ModuleFilter.active => state == _ModuleState.active,
        _ModuleFilter.completed => state == _ModuleState.completed,
      };
    }).toList(growable: false);
    final totalPages = (filteredModules.length / _pageSize).ceil();
    final page = totalPages == 0 ? 0 : _page.clamp(0, totalPages - 1).toInt();
    final visible =
        filteredModules.skip(page * _pageSize).take(_pageSize).toList();
    final states = <_ModuleState>[
      for (final module in modules) _moduleState(module, progress),
    ];
    final completedModules =
        states.where((state) => state == _ModuleState.completed).length;
    final completedExams = bank.exams
        .where((exam) =>
            _answeredExamQuestions(progress, exam.testNo) >= exam.questionCount)
        .length;
    final bestExamScore = progress.testExamBestScores.values.fold<int>(
      0,
      (best, score) => score > best ? score : best,
    );
    final totalExamSeconds = progress.testExamElapsedSeconds.values.fold<int>(
      0,
      (total, seconds) => total + seconds,
    );
    return PageFrame(
      title: 'Testler',
      subtitle: 'Test Bank içeriğiyle modül, yapı ve özgün test çalışması.',
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SummaryCard(
              counts: bank.counts,
              completedModules: completedModules,
              knownCards: progress.testFlashcardKnownIds.length,
              completedMatching: progress.completedTestMatchingModuleIds.length,
              completedQuickTests: <String>{
                ...progress.testQuickTestBestScores.keys,
                ...progress.manuallyCompletedTestModuleIds,
              }.length,
              completedExams: completedExams,
              testFavorites: progress.testFavoriteWordIds.length,
              knownStructures: progress.testKnownStructureIds.length,
            ),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1040
                  ? 3
                  : constraints.maxWidth >= 640
                      ? 2
                      : 1;
              final width =
                  (constraints.maxWidth - (12 * (columns - 1))) / columns;
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
                        '$completedExams / ${bank.counts.exams} tamamlandı · En iyi %$bestExamScore · ${_formatExamDuration(totalExamSeconds)}',
                    onTap: () => context.go('/tests/exams'),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _FeatureCard(
                    icon: Icons.favorite_outline_rounded,
                    title: 'Favoriler',
                    description:
                        '${progress.testFavoriteWordIds.length} Test Bank kelimesi · Liste ve flash kart',
                    onTap: () => context.go('/tests/favorites'),
                  ),
                ),
              ]);
            }),
            const SizedBox(height: 16),
            Text('Modüller', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            SurfaceCard(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
                    for (final filter in _ModuleFilter.values)
                      ChoiceChip(
                        label: Text(filter.label),
                        selected: _filter == filter,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setState(() {
                          _filter = filter;
                          _page = 0;
                        }),
                      ),
                  ]),
                  const SizedBox(height: 6),
                  Divider(
                      height: 1,
                      color: AppThemeTokens.of(context).surfaceBorder),
                  const SizedBox(height: 6),
                  _Pagination(
                    currentPage: page,
                    totalPages: totalPages,
                    totalItems: filteredModules.length,
                    onChanged: (next) => setState(() => _page = next),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
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
                            state: _moduleState(module, progress),
                            known: progress.testFlashcardKnownIds
                                .where(
                                    (id) => id.startsWith('${module.id}-word-'))
                                .length,
                            matchingDone: progress
                                .completedTestMatchingModuleIds
                                .contains(module.moduleNo.toString()),
                            matchingBest: progress.testMatchingBestScores[
                                module.moduleNo.toString()],
                            quickBest: progress.testQuickTestBestScores[
                                module.moduleNo.toString()],
                            manuallyCompleted: progress
                                .manuallyCompletedTestModuleIds
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
    required this.completedModules,
    required this.knownCards,
    required this.completedMatching,
    required this.completedQuickTests,
    required this.completedExams,
    required this.testFavorites,
    required this.knownStructures,
  });
  final TestBankCounts counts;
  final int completedModules;
  final int knownCards;
  final int completedMatching;
  final int completedQuickTests;
  final int completedExams;
  final int testFavorites;
  final int knownStructures;

  @override
  Widget build(BuildContext context) {
    final primaryItems = <(String, String)>[
      ('Tamamlanan modül', '$completedModules / ${counts.modules}'),
      ('Öğrenilen kart', '$knownCards / ${counts.wordRows}'),
      ('Eşleştirme', '$completedMatching / ${counts.modules}'),
      ('Hızlı test', '$completedQuickTests / ${counts.modules}'),
    ];
    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth >= 760
            ? (constraints.maxWidth - 36) / 4
            : (constraints.maxWidth - 12) / 2;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: primaryItems
                  .map((item) => SizedBox(
                        width: width,
                        child: _SummaryMetric(value: item.$2, label: item.$1),
                      ))
                  .toList(growable: false),
            ),
            const SizedBox(height: 10),
            Divider(color: AppThemeTokens.of(context).surfaceBorder),
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: <Widget>[
                _InlineSummary(
                  label: 'Özgün test',
                  value: '$completedExams / ${counts.exams}',
                ),
                _InlineSummary(
                  label: 'Test favorileri',
                  value: '$testFavorites',
                ),
                _InlineSummary(
                  label: 'Yapı ilerlemesi',
                  value: '$knownStructures / ${counts.structures}',
                ),
              ],
            ),
          ],
        );
      }),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(value, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class _InlineSummary extends StatelessWidget {
  const _InlineSummary({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodySmall,
          children: <InlineSpan>[
            TextSpan(
              text: '$value ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: label),
          ],
        ),
      );
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
      padding: const EdgeInsets.all(14),
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
    required this.state,
    required this.known,
    required this.matchingDone,
    required this.matchingBest,
    required this.quickBest,
    required this.manuallyCompleted,
  });
  final TestModuleSummary module;
  final _ModuleState state;
  final int known;
  final bool matchingDone;
  final int? matchingBest;
  final int? quickBest;
  final bool manuallyCompleted;

  @override
  Widget build(BuildContext context) {
    final completedItems = known.clamp(0, module.wordCount).toInt() +
        ((matchingDone || manuallyCompleted) ? 1 : 0) +
        ((quickBest != null || manuallyCompleted) ? 1 : 0);
    final totalItems = module.wordCount + 2;
    return SurfaceCard(
      onTap: () => context.go('/tests/module/${module.moduleNo}'),
      padding: const EdgeInsets.all(14),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(children: <Widget>[
              Text('Modül ${module.moduleNo}',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              _StatusPill(state: state),
            ]),
            const SizedBox(height: 6),
            Text('${module.wordCount} kelime',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: completedItems / totalItems),
            const SizedBox(height: 7),
            Text(
              '$completedItems / $totalItems adım · $known / ${module.wordCount} kart bilindi',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (matchingBest != null || quickBest != null) ...<Widget>[
              const SizedBox(height: 5),
              Text(
                [
                  if (matchingBest != null) 'Eşleştirme: %$matchingBest',
                  if (quickBest != null) 'Hızlı test: %$quickBest',
                ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (manuallyCompleted &&
                (matchingBest == null || quickBest == null)) ...<Widget>[
              const SizedBox(height: 5),
              Text('Manuel olarak tamamlandı',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: () => context.go('/tests/module/${module.moduleNo}'),
                child: Text(switch (state) {
                  _ModuleState.notStarted => 'Başla',
                  _ModuleState.active => 'Devam et',
                  _ModuleState.completed => 'Tekrar et',
                }),
              ),
            ),
          ]),
    );
  }
}

enum _ModuleFilter {
  all('Tümü'),
  active('Devam Eden'),
  completed('Tamamlanan');

  const _ModuleFilter(this.label);
  final String label;
}

enum _ModuleState { notStarted, active, completed }

_ModuleState _moduleState(
  TestModuleSummary module,
  LocalProgressSnapshot progress,
) {
  final known = progress.testFlashcardKnownIds
      .where((id) => id.startsWith('${module.id}-word-'))
      .length;
  final matching = progress.completedTestMatchingModuleIds
      .contains(module.moduleNo.toString());
  final quick =
      progress.testQuickTestBestScores.containsKey(module.moduleNo.toString());
  final manuallyCompleted = progress.manuallyCompletedTestModuleIds
      .contains(module.moduleNo.toString());
  if (manuallyCompleted || (known >= module.wordCount && matching && quick)) {
    return _ModuleState.completed;
  }
  if (known > 0 ||
      matching ||
      quick ||
      progress.testLastModuleNo == module.moduleNo) {
    return _ModuleState.active;
  }
  return _ModuleState.notStarted;
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.state});
  final _ModuleState state;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final (label, icon, color) = switch (state) {
      _ModuleState.notStarted => (
          'Başlanmadı',
          Icons.circle_outlined,
          tokens.secondaryText
        ),
      _ModuleState.active => (
          'Devam ediyor',
          Icons.play_circle_outline_rounded,
          tokens.accent
        ),
      _ModuleState.completed => (
          'Tamamlandı',
          Icons.check_circle_outline_rounded,
          tokens.success
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Icon(icon, color: color, size: 15),
        const SizedBox(width: 4),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w700)),
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

String _formatExamDuration(int seconds) {
  final duration = Duration(seconds: seconds < 0 ? 0 : seconds);
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final secs = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return duration.inHours == 0
      ? '$minutes:$secs'
      : '${duration.inHours}:$minutes:$secs';
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
  Widget build(BuildContext context) => Wrap(
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
      );
}
