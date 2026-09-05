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
  String? _level;
  String? _status;

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
        )),
      ),
      error: (error, _) => DataLoadErrorPage(
        message: error.toString(),
        onRetry: () => ref.invalidate(studyModulesProvider),
      ),
      data: (allModules) {
        final shown = allModules.where((module) {
          return (_topic == null || module.mainTopic == _topic) &&
              (_grammar == null || module.grammarFocus == _grammar) &&
              (_level == null || module.levelProfile == _level) &&
              (_status == null || module.status == _status);
        }).toList(growable: false);
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
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    _StudyDropdown(
                      label: 'Ana konu',
                      value: _topic,
                      values: allModules.map((item) => item.mainTopic),
                      onChanged: (value) => setState(() => _topic = value),
                    ),
                    _StudyDropdown(
                      label: 'Gramer',
                      value: _grammar,
                      values: allModules.map((item) => item.grammarFocus),
                      onChanged: (value) => setState(() => _grammar = value),
                    ),
                    _StudyDropdown(
                      label: 'Seviye',
                      value: _level,
                      values: allModules.map((item) => item.levelProfile),
                      onChanged: (value) => setState(() => _level = value),
                    ),
                    _StudyDropdown(
                      label: 'Durum',
                      value: _status,
                      values: allModules.map((item) => item.status),
                      onChanged: (value) => setState(() => _status = value),
                    ),
                    if (_topic != null ||
                        _grammar != null ||
                        _level != null ||
                        _status != null)
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _topic = null;
                          _grammar = null;
                          _level = null;
                          _status = null;
                        }),
                        icon: const Icon(Icons.clear_rounded),
                        label: const Text('Filtreleri temizle'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (shown.isEmpty)
                const SurfaceCard(
                    child: Text('Bu filtrelerle eşleşen modül yok.')),
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
                          .map((module) => SizedBox(
                                width: width,
                                child: _StudyModuleCard(
                                  module: module,
                                  uniformHeight: twoColumns,
                                ),
                              ))
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
    required this.values,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final Iterable<String> values;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = values.toSet().toList()..sort();
    return SizedBox(
      width: 210,
      child: DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: value,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: <DropdownMenuItem<String>>[
          const DropdownMenuItem<String>(value: null, child: Text('Tümü')),
          ...options.map((item) => DropdownMenuItem<String>(
                value: item,
                child: Text(item, overflow: TextOverflow.ellipsis),
              )),
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
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 20,
        runSpacing: 14,
        children: <Widget>[
          _Stat(
              label: 'Devam eden',
              value: last.isEmpty ? '—' : 'Modül ${last.first.number}'),
          _Stat(label: 'Tamamlanan', value: '$completed / ${modules.length}'),
          _Stat(label: 'Son bölüm', value: progress.studyLastSection ?? '—'),
          _Stat(label: 'Test başarı', value: successRate),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 130,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(value, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 3),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ]),
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
    final completed = finished == 7;
    final continuing = finished > 0 && !completed;
    final total = 7;
    return SurfaceCard(
      onTap: () => context.go('/study/module/${module.id}'),
      child: SizedBox(
        height: uniformHeight ? 400 : null,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(children: <Widget>[
                Expanded(
                    child: Text('Modül ${module.number}',
                        style: Theme.of(context).textTheme.titleLarge)),
                Chip(
                    label: Text(completed
                        ? 'Tamamlandı'
                        : continuing
                            ? 'Devam ediyor'
                            : 'Yeni')),
              ]),
              const SizedBox(height: 8),
              Text(module.mainTopic,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              SizedBox(
                height: 44,
                child: Text(
                  module.subtopic,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 10),
              Text('Gramer', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 3),
              SizedBox(
                height: 42,
                child: Text(
                  module.grammarFocus,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: uniformHeight ? 88 : null,
                child: Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                  _Meta(label: module.levelProfile),
                  _Meta(label: '${module.counts.words} Kelime'),
                  _Meta(label: '${module.counts.sentences} Cümle'),
                  _Meta(label: 'Reading'),
                  _Meta(label: '${module.counts.translations} Çeviri'),
                  _Meta(label: '${module.counts.testQuestions} Test'),
                ]),
              ),
              if (uniformHeight) const Spacer(),
              const SizedBox(height: 14),
              LinearProgressIndicator(value: finished / total),
              const SizedBox(height: 8),
              Text('$finished / $total bölüm',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => context.go('/study/module/${module.id}'),
                  icon: Icon(continuing
                      ? Icons.play_arrow_rounded
                      : Icons.arrow_forward_rounded),
                  label: Text(continuing ? 'Devam Et' : 'Başla'),
                ),
              ),
            ]),
      ),
    );
  }
}

int studySectionProgress(LocalProgressSnapshot progress, String moduleId) {
  if (progress.completedStudyModuleIds.contains(moduleId)) return 7;
  return progress.completedStudySectionKeys
      .where((key) => key.startsWith('$moduleId:'))
      .length
      .clamp(0, 7)
      .toInt();
}

class _Meta extends StatelessWidget {
  const _Meta({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Chip(
        visualDensity: VisualDensity.compact,
        label: Text(label, overflow: TextOverflow.ellipsis),
      );
}
