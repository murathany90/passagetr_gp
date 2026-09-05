import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/content_providers.dart';
import '../../core/local_progress.dart';
import '../../models/study_models.dart';
import '../../repositories/local_progress_repository.dart';
import '../common/page_parts.dart';

class StudyPage extends ConsumerStatefulWidget {
  const StudyPage({super.key});

  @override
  ConsumerState<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends ConsumerState<StudyPage> {
  String? _topic;
  String? _grammar;

  @override
  Widget build(BuildContext context) {
    final modules = ref.watch(studyModulesProvider);
    return modules.when(
      loading: () => const PageFrame(
        title: 'Çalışma',
        subtitle: 'Çalışma modülleri hazırlanıyor.',
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(40),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
      error: (error, _) => DataLoadErrorPage(
        message: error.toString(),
        onRetry: () => ref.invalidate(studyModulesProvider),
      ),
      data: (allModules) {
        final grammarValues = allModules
            .where((module) => _topic == null || module.mainTopic == _topic)
            .map((module) => module.grammarFocus)
            .toSet();
        if (_grammar != null && !grammarValues.contains(_grammar)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _grammar = null);
          });
        }
        final shown = allModules
            .where(
              (module) =>
                  (_topic == null || module.mainTopic == _topic) &&
                  (_grammar == null || module.grammarFocus == _grammar),
            )
            .toList(growable: false);
        return PageFrame(
          title: 'Çalışma',
          subtitle: 'Kaynak tabanlı YDS çalışma modülleri.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _StudyStats(modules: allModules),
              const SizedBox(height: 16),
              SurfaceCard(
                padding: const EdgeInsets.all(16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final twoColumns = constraints.maxWidth >= 300;
                    final width = twoColumns
                        ? (constraints.maxWidth - 10) / 2
                        : constraints.maxWidth;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: <Widget>[
                        _StudyDropdown(
                          label: 'Ana konu',
                          value: _topic,
                          width: width,
                          values: allModules.map((item) => item.mainTopic),
                          onChanged: (value) => setState(() {
                            _topic = value;
                            final availableGrammar = allModules
                                .where(
                                  (module) =>
                                      value == null ||
                                      module.mainTopic == value,
                                )
                                .map((module) => module.grammarFocus);
                            if (_grammar != null &&
                                !availableGrammar.contains(_grammar)) {
                              _grammar = null;
                            }
                          }),
                        ),
                        _StudyDropdown(
                          label: 'Gramer',
                          value: _grammar,
                          width: width,
                          values: grammarValues,
                          onChanged: (value) =>
                              setState(() => _grammar = value),
                        ),
                        if (_topic != null || _grammar != null)
                          TextButton.icon(
                            onPressed: () => setState(() {
                              _topic = null;
                              _grammar = null;
                            }),
                            icon: const Icon(Icons.clear_rounded),
                            label: const Text('Filtreleri temizle'),
                          ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              if (shown.isEmpty)
                const SurfaceCard(
                  child: Text('Bu filtrelerle eşleşen modül yok.'),
                ),
              if (shown.isNotEmpty)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final twoColumns = constraints.maxWidth >= 720;
                    final width = twoColumns
                        ? (constraints.maxWidth - 14) / 2
                        : constraints.maxWidth;
                    return Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: shown
                          .map(
                            (module) => SizedBox(
                              width: width,
                              child: _StudyModuleCard(
                                module: module,
                                uniformHeight: twoColumns,
                              ),
                            ),
                          )
                          .toList(growable: false),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _StudyDropdown extends StatelessWidget {
  const _StudyDropdown({
    required this.label,
    required this.value,
    required this.width,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final double width;
  final Iterable<String> values;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = values.toSet().toList()..sort();
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: value,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: <DropdownMenuItem<String>>[
          const DropdownMenuItem<String>(value: null, child: Text('Tümü')),
          ...options.map(
            (item) => DropdownMenuItem<String>(
              value: item,
              child: Text(item, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _StudyStats extends ConsumerWidget {
  const _StudyStats({required this.modules});

  final List<StudyModuleSummary> modules;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(localProgressProvider);
    final last = modules.where((item) => item.id == progress.studyLastModuleId);
    final completed = modules
        .where((module) => studySectionProgress(progress, module.id) == 7)
        .length;
    final answered = progress.studyQuestionCorrectness.length;
    final correct = progress.studyQuestionCorrectness.values
        .where((isCorrect) => isCorrect)
        .length;
    final successRate =
        answered == 0 ? '—' : '${(correct * 100 / answered).round()}%';
    final stats = <Widget>[
      _Stat(
        label: 'Devam eden',
        value: last.isEmpty ? '—' : 'Modül ${last.first.number}',
      ),
      _Stat(label: 'Tamamlanan', value: '$completed / ${modules.length}'),
      _Stat(label: 'Son bölüm', value: progress.studyLastSection ?? '—'),
      _Stat(label: 'Test başarı', value: successRate),
    ];
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 620) {
            return Row(
              children: stats
                  .map((stat) => Expanded(child: stat))
                  .toList(growable: false),
            );
          }
          final width = (constraints.maxWidth - 10) / 2;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: stats
                .map((stat) => SizedBox(width: width, child: stat))
                .toList(growable: false),
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(value, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 3),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}

class _StudyModuleCard extends ConsumerWidget {
  const _StudyModuleCard({
    required this.module,
    required this.uniformHeight,
  });
  final StudyModuleSummary module;
  final bool uniformHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(localProgressProvider);
    final finished = studySectionProgress(progress, module.id);
    final continuing = finished > 0 && finished < 7;
    const total = 7;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(18, 15, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            height: 66,
            child: Text(
              _bilingualTitle(module.subtopic, module.subtopicTr),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 8),
          _CardLabel(label: 'Ana konu', value: module.mainTopic),
          const SizedBox(height: 10),
          _CardLabel(
            label: 'Gramer',
            value: module.grammarFocus,
            maxLines: 2,
          ),
          if (uniformHeight) const Spacer() else const SizedBox(height: 18),
          LinearProgressIndicator(value: finished / total),
          const SizedBox(height: 7),
          Text(
            '$finished / $total bölüm',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => context.go('/study/module/${module.id}'),
              icon: Icon(
                continuing
                    ? Icons.play_arrow_rounded
                    : Icons.arrow_forward_rounded,
              ),
              label: Text(continuing ? 'Devam Et' : 'Başla'),
            ),
          ),
        ],
      ),
    );
    return SurfaceCard(
      padding: EdgeInsets.zero,
      onTap: () => context.go('/study/module/${module.id}'),
      child: SizedBox(
        height: uniformHeight ? 372 : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                gradient: _moduleAccentGradient(module.number),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Text(
                'Modül ${module.number.toString().padLeft(2, '0')}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            if (uniformHeight) Expanded(child: content) else content,
          ],
        ),
      ),
    );
  }
}

class _CardLabel extends StatelessWidget {
  const _CardLabel({
    required this.label,
    required this.value,
    this.maxLines = 1,
  });

  final String label;
  final String value;
  final int maxLines;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      );
}

String _bilingualTitle(String english, String turkish) =>
    turkish.trim().isEmpty ? english : '$english ($turkish)';

LinearGradient _moduleAccentGradient(int moduleNumber) {
  const palettes = <List<Color>>[
    <Color>[Color(0xFF1D4ED8), Color(0xFF1E3A8A)],
    <Color>[Color(0xFF0F766E), Color(0xFF115E59)],
    <Color>[Color(0xFF6D28D9), Color(0xFF4C1D95)],
    <Color>[Color(0xFF9A3412), Color(0xFF7C2D12)],
    <Color>[Color(0xFF075985), Color(0xFF0C4A6E)],
    <Color>[Color(0xFF047857), Color(0xFF065F46)],
  ];
  final colors = palettes[(moduleNumber - 1) % palettes.length];
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: colors,
  );
}

int studySectionProgress(LocalProgressSnapshot progress, String moduleId) {
  if (progress.completedStudyModuleIds.contains(moduleId)) return 7;
  return progress.completedStudySectionKeys
      .where((key) => key.startsWith('$moduleId:'))
      .length
      .clamp(0, 7)
      .toInt();
}
