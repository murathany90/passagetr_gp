import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/content_providers.dart';
import '../../core/local_progress.dart';
import '../../core/app_theme_tokens.dart';
import '../../models/content_models.dart';
import '../../models/study_models.dart';
import '../common/page_parts.dart';
import '../tts/student_tts_icon_button.dart';
import '../words/word_detail_sheet.dart';
import 'study_word_detail_sheet.dart';

/// Opens the shared word-detail sheet only for a literal canonical match.
/// Study content remains the trusted fallback for every unbound headword;
/// neither a fuzzy lookup nor a semantically different alias is acceptable.
Future<void> showStudyWordDetail(
  BuildContext context,
  WidgetRef ref,
  StudyWord studyWord,
) async {
  WordEntry? canonicalWord;
  final exactReference = studyWord.sourceWordRef.trim().toLowerCase();
  try {
    final loadedWords = ref.read(wordsProvider).valueOrNull ??
        await ref.read(staticContentRepositoryProvider).loadWords();
    for (final word in loadedWords) {
      if (word.enWord.trim().toLowerCase() == exactReference) {
        canonicalWord = word;
        break;
      }
    }
  } catch (_) {
    // The Study workbook still contains its own vetted word detail.
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => canonicalWord == null
        ? StudyWordDetailSheet(word: studyWord)
        : WordDetailSheet(word: canonicalWord),
  );
}

class StudyModulePage extends ConsumerStatefulWidget {
  const StudyModulePage({super.key, required this.moduleId});
  final String moduleId;

  @override
  ConsumerState<StudyModulePage> createState() => _StudyModulePageState();
}

class _StudyModulePageState extends ConsumerState<StudyModulePage> {
  static const _sections = <_StudySection>[
    _StudySection.words,
    _StudySection.sentences,
    _StudySection.reading,
    _StudySection.translations,
    _StudySection.structures,
    _StudySection.test,
    _StudySection.review,
  ];

  late _StudySection _section;

  @override
  void initState() {
    super.initState();
    _section = _StudySection.fromStorage(
      ref.read(localProgressProvider).studyLastModuleId == widget.moduleId
          ? ref.read(localProgressProvider).studyLastSection
          : null,
    );
  }

  void _setSection(_StudySection section) {
    setState(() => _section = section);
    ref.read(localProgressProvider.notifier).setStudyLocation(
          moduleId: widget.moduleId,
          section: section.storageValue,
        );
  }

  @override
  Widget build(BuildContext context) {
    final compatibility = ref.watch(studyQuestionCompatibilityProvider);
    if (compatibility.isLoading) {
      return const PageFrame(
        title: 'Çalışma modülü',
        subtitle: 'Çalışma ilerlemesi doğrulanıyor.',
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(40),
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }
    if (compatibility.hasError) {
      return DataLoadErrorPage(
        message: compatibility.error.toString(),
        onRetry: () => ref.invalidate(studyQuestionCompatibilityProvider),
      );
    }
    final detail = ref.watch(studyModuleDetailProvider(widget.moduleId));
    return detail.when(
      loading: () => const PageFrame(
        title: 'Çalışma modülü',
        subtitle: 'İçerik hazırlanıyor.',
        child: Center(
            child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        )),
      ),
      error: (error, _) => DataLoadErrorPage(
        message: error.toString(),
        onRetry: () =>
            ref.invalidate(studyModuleDetailProvider(widget.moduleId)),
      ),
      data: (module) {
        final progress = ref.watch(localProgressProvider);
        final sectionDone = progress.completedStudySectionKeys.contains(
          '${module.module.id}:${_section.storageValue}',
        );
        return PageFrame(
          title: 'Modül ${module.module.number}',
          subtitle: module.module.mainTopic,
          actions: <Widget>[
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => _confirmReset(module.module.id),
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('İlerlemeyi sıfırla'),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => _setSection(_StudySection.words),
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Başa dön'),
            ),
          ],
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _StudyModuleHeader(module: module.module),
                const SizedBox(height: 10),
                _StudySectionTabs(
                  sections: _sections,
                  selected: _section,
                  onSelected: _setSection,
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.end,
                  children: <Widget>[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: sectionDone
                          ? null
                          : () => ref
                              .read(localProgressProvider.notifier)
                              .markStudySectionCompleted(
                                moduleId: module.module.id,
                                section: _section.storageValue,
                                sectionCount: _sections.length,
                              ),
                      icon: Icon(sectionDone
                          ? Icons.check_circle_rounded
                          : Icons.task_alt_rounded),
                      label: Text(
                        sectionDone ? 'Bölüm tamamlandı' : 'Bölümü tamamla',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _section.build(module),
              ]),
        );
      },
    );
  }

  Future<void> _confirmReset(String moduleId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Modül ilerlemesi silinsin mi?'),
        content: const Text(
          'Yalnız bu modülün bölüm ilerlemesi, Reading/Test cevapları, '
          'skoru ve son bölüm bilgisi silinir. Favorileriniz ve diğer '
          'modüller etkilenmez.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('İlerlemeyi sıfırla'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    ref.read(localProgressProvider.notifier).resetStudyModuleProgress(moduleId);
    setState(() => _section = _StudySection.words);
  }
}

class _StudyModuleHeader extends StatelessWidget {
  const _StudyModuleHeader({required this.module});

  final StudyModuleSummary module;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return SizedBox(
      width: double.infinity,
      child: SurfaceCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              module.subtopic,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (module.subtopicTr.isNotEmpty) ...<Widget>[
              const SizedBox(height: 3),
              Text(
                '(${module.subtopicTr})',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: tokens.secondaryText),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tokens.surfaceMuted,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: tokens.surfaceBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.account_tree_outlined,
                    size: 18,
                    color: tokens.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('Gramer',
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 2),
                        Text(
                          module.grammarFocus,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (module.grammarFocusTr.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(
                            '(${module.grammarFocusTr})',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: tokens.secondaryText),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              module.levelProfile,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: tokens.secondaryText),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudySectionTabs extends StatelessWidget {
  const _StudySectionTabs({
    required this.sections,
    required this.selected,
    required this.onSelected,
  });

  final List<_StudySection> sections;
  final _StudySection selected;
  final ValueChanged<_StudySection> onSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 720) {
            return SizedBox(
              width: double.infinity,
              height: 54,
              child: Row(children: _tabs(sections, compact: false)),
            );
          }
          return Column(
            children: <Widget>[
              SizedBox(
                width: double.infinity,
                height: 58,
                child: Row(children: _tabs(sections.take(4), compact: true)),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: Row(children: _tabs(sections.skip(4), compact: true)),
              ),
            ],
          );
        },
      );

  List<Widget> _tabs(
    Iterable<_StudySection> values, {
    required bool compact,
  }) {
    final items = values.toList(growable: false);
    return <Widget>[
      for (final entry in items.indexed) ...<Widget>[
        Expanded(
          child: _StudySectionTab(
            section: entry.$2,
            selected: entry.$2 == selected,
            compact: compact,
            onTap: () => onSelected(entry.$2),
          ),
        ),
        if (entry.$1 != items.length - 1) const SizedBox(width: 6),
      ],
    ];
  }
}

class _StudySectionTab extends StatelessWidget {
  const _StudySectionTab({
    required this.section,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final _StudySection section;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final foreground =
        selected ? Theme.of(context).colorScheme.onPrimary : tokens.primaryText;
    return Semantics(
      button: true,
      selected: selected,
      label: section.label,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? tokens.accent : tokens.surfaceMuted,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? tokens.accent : tokens.surfaceBorder,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
              child: compact
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(section.icon, size: 16, color: foreground),
                        const SizedBox(height: 3),
                        Text(
                          section.compactLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: foreground,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(section.icon, size: 16, color: foreground),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            section.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: foreground,
                                      fontWeight: FontWeight.w800,
                                    ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _StudySection {
  words('Kelime', 'Kelime', 'words', Icons.style_outlined),
  sentences(
      'Cümle & Gramer', 'Gramer', 'sentences', Icons.account_tree_outlined),
  reading('Reading', 'Okuma', 'reading', Icons.menu_book_outlined),
  translations('Çeviri', 'Çeviri', 'translations', Icons.translate_rounded),
  structures('YDS Yapıları', 'YDS', 'structures', Icons.hub_outlined),
  test('Test', 'Test', 'test', Icons.quiz_outlined),
  review('Review', 'Tekrar', 'review', Icons.refresh_rounded);

  const _StudySection(
    this.label,
    this.compactLabel,
    this.storageValue,
    this.icon,
  );
  final String label;
  final String compactLabel;
  final String storageValue;
  final IconData icon;

  static _StudySection fromStorage(String? value) => values.firstWhere(
        (item) => item.storageValue == value,
        orElse: () => _StudySection.words,
      );

  Widget build(StudyModuleDetail detail) => switch (this) {
        _StudySection.words => _StudyWords(words: detail.words),
        _StudySection.sentences => _StudySentences(sentences: detail.sentences),
        _StudySection.reading => _StudyReading(
            reading: detail.reading,
            fallbackTitle: detail.module.subtopic,
            targetWords: detail.words,
          ),
        _StudySection.translations =>
          _StudyTranslations(translations: detail.translations),
        _StudySection.structures =>
          _StudyStructures(structures: detail.structures),
        _StudySection.test => _StudyTest(
            moduleId: detail.module.id,
            questions: detail.testQuestions,
          ),
        _StudySection.review => _StudyReview(items: detail.review),
      };
}

class _StudyWords extends StatelessWidget {
  const _StudyWords({required this.words});
  final List<StudyWord> words;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('${words.length} hedef kelime',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          ...words.map((word) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: _StudyWordCard(word: word),
                ),
              )),
        ],
      );
}

class _StudyWordCard extends ConsumerStatefulWidget {
  const _StudyWordCard({required this.word});
  final StudyWord word;

  @override
  ConsumerState<_StudyWordCard> createState() => _StudyWordCardState();
}

class _StudyWordCardState extends ConsumerState<_StudyWordCard> {
  bool _details = false;

  @override
  Widget build(BuildContext context) {
    final word = widget.word;
    final tts = ref.watch(studentTtsControllerProvider);
    final speaking = tts.isSpeaking && tts.activeWordId == word.id;
    final grouped = <String, List<StudyWordItem>>{};
    for (final item in word.items) {
      grouped.putIfAbsent(item.type, () => <StudyWordItem>[]).add(item);
    }
    return SizedBox(
      width: double.infinity,
      child: SurfaceCard(
        padding: const EdgeInsets.all(16),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 36),
                              alignment: Alignment.centerLeft,
                            ),
                            onPressed: () =>
                                showStudyWordDetail(context, ref, word),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Flexible(
                                  child: Text(
                                    '${word.order}. ${word.headword}',
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.open_in_new_rounded, size: 16),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${word.meaningTr} · ${word.pos}',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color:
                                      AppThemeTokens.of(context).secondaryText,
                                ),
                          ),
                        ])),
                    StudentTtsIconButton(
                      tooltip: 'Kelimeyi dinle',
                      isSpeaking: speaking,
                      isInitializing:
                          tts.isInitializing && tts.activeWordId == word.id,
                      isUnavailable: tts.isUnavailable,
                      onPlay: () => ref
                          .read(studentTtsControllerProvider.notifier)
                          .playDictionaryEntry(
                              entryId: word.id, text: word.headword),
                      onStop: () => ref
                          .read(studentTtsControllerProvider.notifier)
                          .stop(),
                    ),
                  ]),
              const SizedBox(height: 10),
              Text(
                word.contextMeaning,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppThemeTokens.of(context).secondaryText),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => setState(() => _details = !_details),
                icon: Icon(_details
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded),
                label: Text(_details ? 'Ayrıntıyı gizle' : 'Ayrıntı göster'),
              ),
              if (_details) ...<Widget>[
                const SizedBox(height: 14),
                _DetailBlock(
                  label: 'YDS notu',
                  text: word.ydsNote,
                  textIsSecondary: true,
                ),
                _DetailBlock(
                    label: 'Örnek',
                    text: word.exampleEn,
                    secondary: word.exampleTr,
                    emphasizeText: true),
                ...grouped.entries.map((entry) => _WordItemsBlock(
                      label: _wordItemLabel(entry.key),
                      items: entry.value,
                    )),
              ],
            ]),
      ),
    );
  }
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({
    required this.label,
    required this.text,
    this.secondary,
    this.emphasizeText = false,
    this.textIsSecondary = false,
  });
  final String label;
  final String text;
  final String? secondary;
  final bool emphasizeText;
  final bool textIsSecondary;
  @override
  Widget build(BuildContext context) {
    if (text.isEmpty && (secondary?.isEmpty ?? true)) {
      return const SizedBox.shrink();
    }
    final tokens = AppThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            if (text.isNotEmpty) const SizedBox(height: 3),
            if (text.isNotEmpty)
              Text(
                text,
                style: emphasizeText
                    ? Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w700)
                    : textIsSecondary
                        ? Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: tokens.secondaryText)
                        : null,
              ),
            if (secondary != null && secondary!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 3),
              Text(secondary!, style: TextStyle(color: tokens.secondaryText)),
            ],
          ]),
    );
  }
}

class _WordItemsBlock extends StatelessWidget {
  const _WordItemsBlock({required this.label, required this.items});
  final String label;
  final List<StudyWordItem> items;
  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            ...items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text.rich(
                    TextSpan(
                      style: Theme.of(context).textTheme.bodyLarge,
                      children: <InlineSpan>[
                        if (item.subtype.isNotEmpty)
                          TextSpan(text: '${item.subtype}: '),
                        if (item.valueEn.isNotEmpty)
                          TextSpan(
                            text: item.valueEn,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        if (item.valueTr.isNotEmpty)
                          TextSpan(
                            text: ' — ${item.valueTr}',
                            style: TextStyle(color: tokens.secondaryText),
                          ),
                        if (item.usageNote.isNotEmpty)
                          TextSpan(
                            text: ' (${item.usageNote})',
                            style: TextStyle(color: tokens.secondaryText),
                          ),
                      ],
                    ),
                  ),
                )),
          ]),
    );
  }
}

class _StudySentences extends StatefulWidget {
  const _StudySentences({required this.sentences});
  final List<StudySentence> sentences;
  @override
  State<_StudySentences> createState() => _StudySentencesState();
}

class _StudySentencesState extends State<_StudySentences> {
  final Set<int> _translations = <int>{};
  final Set<int> _analysis = <int>{};
  @override
  Widget build(BuildContext context) => Column(
          children: widget.sentences.map((sentence) {
        final showTr = _translations.contains(sentence.order);
        final showAnalysis = _analysis.contains(sentence.order);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SizedBox(
            width: double.infinity,
            child: SurfaceCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('${sentence.order}. ${sentence.english}',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    _StudySentenceActions(
                      showTranslation: showTr,
                      showAnalysis: showAnalysis,
                      onToggleTranslation: () => setState(() => showTr
                          ? _translations.remove(sentence.order)
                          : _translations.add(sentence.order)),
                      onToggleAnalysis: () => setState(() => showAnalysis
                          ? _analysis.remove(sentence.order)
                          : _analysis.add(sentence.order)),
                    ),
                    if (showTr) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                        sentence.turkish,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppThemeTokens.of(context).secondaryText,
                            ),
                      )
                    ],
                    if (showAnalysis) ...<Widget>[
                      const SizedBox(height: 10),
                      ...sentence.analysis.entries.map((entry) => Padding(
                            padding: const EdgeInsets.only(bottom: 7),
                            child: _AnalysisTile(
                              label: entry.key,
                              text: entry.value,
                            ),
                          )),
                    ],
                  ]),
            ),
          ),
        );
      }).toList(growable: false));
}

class _StudySentenceActions extends StatelessWidget {
  const _StudySentenceActions({
    required this.showTranslation,
    required this.showAnalysis,
    required this.onToggleTranslation,
    required this.onToggleAnalysis,
  });

  final bool showTranslation;
  final bool showAnalysis;
  final VoidCallback onToggleTranslation;
  final VoidCallback onToggleAnalysis;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 146,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onToggleTranslation,
              icon: const Icon(Icons.translate_rounded),
              label: Text(
                showTranslation ? 'Çeviriyi gizle' : 'Çeviriyi göster',
              ),
            ),
          ),
          SizedBox(
            width: 126,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onToggleAnalysis,
              icon: const Icon(Icons.account_tree_outlined),
              label: Text(showAnalysis ? 'Analizi gizle' : 'Analizi aç'),
            ),
          ),
        ],
      );
}

class _AnalysisTile extends StatelessWidget {
  const _AnalysisTile({
    required this.label,
    required this.text,
    this.asReadableList = false,
  });
  final String label;
  final String text;
  final bool asReadableList;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            asReadableList ? _ReadableAnalysisText(text: text) : Text(text),
          ]),
    );
  }
}

class _ReadableAnalysisText extends StatelessWidget {
  const _ReadableAnalysisText({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final withNumberedLines = text.replaceAllMapped(
      RegExp(r'\s+(?=\d+\.\s)'),
      (_) => '\n',
    );
    final parts =
        (text.contains('|') ? text.split('|') : withNumberedLines.split('\n'))
            .map((item) => item.trim())
            .where(
              (item) => item.isNotEmpty && !RegExp(r'^[-—–]+$').hasMatch(item),
            )
            .toList(growable: false);
    if (parts.length < 2) return Text(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: parts
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Text('•'),
                  ),
                  const SizedBox(width: 7),
                  Expanded(child: Text(item)),
                ],
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _StudyReading extends StatefulWidget {
  const _StudyReading({
    required this.reading,
    required this.fallbackTitle,
    required this.targetWords,
  });
  final StudyReading reading;
  final String fallbackTitle;
  final List<StudyWord> targetWords;

  @override
  State<_StudyReading> createState() => _StudyReadingState();
}

class _StudyReadingState extends State<_StudyReading> {
  bool _analysisVisible = false;

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        SizedBox(
          width: double.infinity,
          child: SurfaceCard(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                      _bilingualText(
                        widget.reading.title.isEmpty
                            ? widget.fallbackTitle
                            : widget.reading.title,
                        widget.reading.titleTr,
                      ),
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.touch_app_outlined,
                        size: 16,
                        color: AppThemeTokens.of(context).secondaryText,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Cümleye tıkla → çevirisini göster · Vurgulu kelimeye tıkla → anlamı gör',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: _InteractiveReading(
                      sentences: widget.reading.sentencePairs,
                      words: widget.targetWords,
                    ),
                  ),
                ]),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => setState(() => _analysisVisible = !_analysisVisible),
          icon: Icon(_analysisVisible
              ? Icons.expand_less_rounded
              : Icons.analytics_outlined),
          label: Text(_analysisVisible ? 'Analizi gizle' : 'Metni analiz et'),
        ),
        if (_analysisVisible) ...<Widget>[
          const SizedBox(height: 10),
          _ReadingAnalysis(reading: widget.reading),
        ],
        const SizedBox(height: 16),
        Text('Reading soruları',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _QuestionPager(questions: widget.reading.questions),
      ]);
}

class _ReadingAnalysis extends StatelessWidget {
  const _ReadingAnalysis({required this.reading});
  final StudyReading reading;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 720;
          final width =
              wide ? (constraints.maxWidth - 10) / 2 : constraints.maxWidth;
          final items = <(String, String)>[
            ('Ana fikir', reading.mainIdeaTr),
            ('Akış', reading.flowAnalysis),
            ('Önemli kelimeler', reading.importantWords),
            ('Bağlaçlar', reading.connectorMap),
            ('Referanslar', reading.referenceAnalysis),
          ].where((item) => item.$2.isNotEmpty).toList(growable: false);
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: items
                .map((item) => SizedBox(
                      width: width,
                      child: _AnalysisTile(
                        label: item.$1,
                        text: item.$2,
                        asReadableList:
                            item.$1 == 'Akış' || item.$1 == 'Bağlaçlar',
                      ),
                    ))
                .toList(growable: false),
          );
        },
      );
}

class _InteractiveReading extends ConsumerStatefulWidget {
  const _InteractiveReading({required this.sentences, required this.words});
  final List<StudyReadingSentence> sentences;
  final List<StudyWord> words;

  @override
  ConsumerState<_InteractiveReading> createState() =>
      _InteractiveReadingState();
}

class _InteractiveReadingState extends ConsumerState<_InteractiveReading> {
  final Set<int> _revealedSentenceIndexes = <int>{};

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final orderedWords = List<StudyWord>.of(widget.words)
      ..sort((a, b) => b.headword.length.compareTo(a.headword.length));
    final expressions =
        orderedWords.map((word) => RegExp.escape(word.headword)).join('|');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widget.sentences.indexed.map((entry) {
        final index = entry.$1;
        final sentence = entry.$2;
        final revealed = _revealedSentenceIndexes.contains(index);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: revealed ? tokens.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => revealed
                  ? _revealedSentenceIndexes.remove(index)
                  : _revealedSentenceIndexes.add(index)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _InteractiveSentenceText(
                      text: sentence.english,
                      expressionPattern: expressions,
                      words: orderedWords,
                      onTargetWordTap: (word) =>
                          showStudyWordDetail(context, ref, word),
                    ),
                    if (revealed) ...<Widget>[
                      const SizedBox(height: 7),
                      Text(
                        sentence.turkish,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: tokens.secondaryText,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }
}

class _InteractiveSentenceText extends StatelessWidget {
  const _InteractiveSentenceText({
    required this.text,
    required this.expressionPattern,
    required this.words,
    required this.onTargetWordTap,
  });

  final String text;
  final String expressionPattern;
  final List<StudyWord> words;
  final ValueChanged<StudyWord> onTargetWordTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    if (expressionPattern.isEmpty) {
      return Text(text, style: Theme.of(context).textTheme.bodyLarge);
    }
    final matches = RegExp(
      '\\b($expressionPattern)\\b',
      caseSensitive: false,
    ).allMatches(text);
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      final targetText = text.substring(match.start, match.end);
      final target = words.cast<StudyWord?>().firstWhere(
            (word) => word?.headword.toLowerCase() == targetText.toLowerCase(),
            orElse: () => null,
          );
      if (target == null) {
        spans.add(TextSpan(text: targetText));
      } else {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Semantics(
            button: true,
            label: '${target.headword} kelime detayı',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTargetWordTap(target),
              child: Text(
                targetText,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: tokens.accent,
                      fontWeight: FontWeight.w700,
                      backgroundColor: tokens.accent.withValues(alpha: .08),
                      decoration: TextDecoration.underline,
                      decorationColor: tokens.accent.withValues(alpha: .45),
                    ),
              ),
            ),
          ),
        ));
      }
      cursor = match.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return Text.rich(TextSpan(
      style: Theme.of(context).textTheme.bodyLarge,
      children: spans,
    ));
  }
}

class _StudyTranslations extends StatefulWidget {
  const _StudyTranslations({required this.translations});
  final StudyTranslations translations;
  @override
  State<_StudyTranslations> createState() => _StudyTranslationsState();
}

class _StudyTranslationsState extends State<_StudyTranslations> {
  bool _enTr = true;
  final Set<int> _revealed = <int>{};
  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final selectedForeground = Theme.of(context).colorScheme.onPrimary;
    final list = _enTr ? widget.translations.enTr : widget.translations.trEn;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(spacing: 8, children: <Widget>[
            ChoiceChip(
              label: Text(
                'İngilizceden Türkçeye',
                style: TextStyle(
                  color: _enTr ? selectedForeground : tokens.primaryText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              selected: _enTr,
              selectedColor: tokens.accent,
              backgroundColor: tokens.surfaceMuted,
              side: BorderSide(
                color: _enTr ? tokens.accent : tokens.surfaceBorder,
                width: _enTr ? 1.5 : 1,
              ),
              showCheckmark: true,
              onSelected: (_) => setState(() => _enTr = true),
            ),
            ChoiceChip(
              label: Text(
                'Türkçeden İngilizceye',
                style: TextStyle(
                  color: !_enTr ? selectedForeground : tokens.primaryText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              selected: !_enTr,
              selectedColor: tokens.accent,
              backgroundColor: tokens.surfaceMuted,
              side: BorderSide(
                color: !_enTr ? tokens.accent : tokens.surfaceBorder,
                width: !_enTr ? 1.5 : 1,
              ),
              showCheckmark: true,
              onSelected: (_) => setState(() => _enTr = false),
            ),
          ]),
          const SizedBox(height: 12),
          ...list.map((item) {
            final key = (_enTr ? 100 : 200) + item.order;
            final revealed = _revealed.contains(key);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SizedBox(
                width: double.infinity,
                child: SurfaceCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${item.order}. ${item.source}',
                          style: _enTr
                              ? Theme.of(context).textTheme.titleMedium
                              : Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: AppThemeTokens.of(context)
                                        .secondaryText,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            alignment: Alignment.centerLeft,
                            minimumSize: const Size(0, 36),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          onPressed: () => setState(() => revealed
                              ? _revealed.remove(key)
                              : _revealed.add(key)),
                          icon: Icon(revealed
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined),
                          label: Text(
                            revealed ? 'Çeviriyi gizle' : 'Çeviriyi göster',
                          ),
                        ),
                        if (revealed) ...<Widget>[
                          const SizedBox(height: 10),
                          _DetailBlock(
                            label: _enTr
                                ? 'Önerilen çeviri'
                                : 'Önerilen İngilizce',
                            text: item.answer,
                            emphasizeText: !_enTr,
                            textIsSecondary: _enTr,
                          ),
                          _DetailBlock(
                            label: 'Alternatif',
                            text: item.alternative,
                            emphasizeText: !_enTr,
                            textIsSecondary: _enTr,
                          ),
                          _DetailBlock(
                            label: 'İskelet',
                            text: item.skeleton,
                            emphasizeText: !_enTr,
                          ),
                          _DetailBlock(
                            label: 'Anahtar kelimeler',
                            text: item.keyWords,
                            textIsSecondary: _enTr,
                          ),
                          _DetailBlock(
                            label: 'Gramer notu',
                            text: item.grammarNote,
                            textIsSecondary: true,
                          ),
                          _DetailBlock(
                            label: 'Çeviri mantığı',
                            text: item.logic,
                            textIsSecondary: true,
                          ),
                        ],
                      ]),
                ),
              ),
            );
          }),
        ]);
  }
}

class _StudyStructures extends StatelessWidget {
  const _StudyStructures({required this.structures});
  final List<StudyStructure> structures;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<StudyStructure>>{};
    for (final structure in structures) {
      groups
          .putIfAbsent(structure.category, () => <StudyStructure>[])
          .add(structure);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: groups.entries
          .map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _structureLabel(entry.key),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth >= 720
                          ? (constraints.maxWidth - 10) / 2
                          : constraints.maxWidth;
                      return Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: entry.value
                            .map(
                              (item) => SizedBox(
                                width: width,
                                child: _StudyStructureCard(item: item),
                              ),
                            )
                            .toList(growable: false),
                      );
                    },
                  ),
                ],
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _StudyStructureCard extends StatefulWidget {
  const _StudyStructureCard({required this.item});
  final StudyStructure item;

  @override
  State<_StudyStructureCard> createState() => _StudyStructureCardState();
}

class _StudyStructureCardState extends State<_StudyStructureCard> {
  bool _detailsVisible = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final hasDetails = <String>[
      item.confusionNote,
      item.relatedWords,
      item.note,
    ].any((value) => value.isNotEmpty);
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(item.expression, style: Theme.of(context).textTheme.titleSmall),
          if (item.meaningTr.isNotEmpty) ...<Widget>[
            const SizedBox(height: 5),
            Text(
              item.meaningTr,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppThemeTokens.of(context).secondaryText),
            ),
          ],
          if (item.pattern.isNotEmpty)
            _DetailBlock(
              label: 'Pattern',
              text: item.pattern,
              emphasizeText: true,
            ),
          if (item.example.isNotEmpty)
            _DetailBlock(
              label: 'Örnek',
              text: item.example,
              emphasizeText: true,
            ),
          if (hasDetails) ...<Widget>[
            const SizedBox(height: 8),
            TextButton.icon(
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                minimumSize: const Size.fromHeight(40),
              ),
              onPressed: () =>
                  setState(() => _detailsVisible = !_detailsVisible),
              icon: Icon(_detailsVisible
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded),
              label: Text(_detailsVisible ? 'Detayı gizle' : 'Detayı göster'),
            ),
          ],
          if (_detailsVisible) ...<Widget>[
            _DetailBlock(label: 'Dikkat', text: item.confusionNote),
            _DetailBlock(label: 'İlişkili kelimeler', text: item.relatedWords),
            _DetailBlock(label: 'Not', text: item.note),
          ],
        ],
      ),
    );
  }
}

class _StudyTest extends ConsumerWidget {
  const _StudyTest({required this.moduleId, required this.questions});
  final String moduleId;
  final List<StudyQuestion> questions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(localProgressProvider);
    final answers = progress.studyQuestionAnswers;
    final answered =
        questions.where((item) => answers.containsKey(item.id)).length;
    final correct = questions
        .where((item) => progress.studyQuestionCorrectness[item.id] == true)
        .length;
    final complete = questions.isNotEmpty && answered == questions.length;
    final percentage =
        questions.isEmpty ? 0 : (correct * 100 / questions.length).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Text(
            complete
                ? 'Sonuç: $correct / ${questions.length} · %$percentage'
                : '$answered / ${questions.length} cevaplandı',
          ),
        ),
        const SizedBox(height: 12),
        _QuestionPager(
          questions: questions,
          onAllAnswered: () => ref
              .read(localProgressProvider.notifier)
              .markStudySectionCompleted(
                moduleId: moduleId,
                section: _StudySection.test.storageValue,
                sectionCount: _StudyModulePageState._sections.length,
              ),
        ),
      ],
    );
  }
}

class _QuestionPager extends ConsumerStatefulWidget {
  const _QuestionPager({required this.questions, this.onAllAnswered});
  final List<StudyQuestion> questions;
  final VoidCallback? onAllAnswered;

  @override
  ConsumerState<_QuestionPager> createState() => _QuestionPagerState();
}

class _QuestionPagerState extends ConsumerState<_QuestionPager> {
  int _index = 0;
  bool _completionReported = false;

  void _reportCompletionIfNeeded() {
    if (_completionReported || widget.questions.isEmpty) return;
    final answers = ref.read(localProgressProvider).studyQuestionAnswers;
    if (widget.questions.every(answers.containsKey)) {
      _completionReported = true;
      widget.onAllAnswered?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.questions.isEmpty) return const SizedBox.shrink();
    final answers = ref.watch(localProgressProvider).studyQuestionAnswers;
    final answered = widget.questions.where(answers.containsKey).length;
    final safeIndex = _index.clamp(0, widget.questions.length - 1);
    final question = widget.questions[safeIndex];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('$answered / ${widget.questions.length} cevaplandı'),
        const SizedBox(height: 8),
        Text(
          '${safeIndex + 1} / ${widget.questions.length}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        _QuestionCard(
            question: question, onAnswered: _reportCompletionIfNeeded),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            TextButton.icon(
              onPressed: safeIndex == 0
                  ? null
                  : () => setState(() => _index = safeIndex - 1),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Önceki'),
            ),
            TextButton.icon(
              onPressed: safeIndex == widget.questions.length - 1
                  ? null
                  : () => setState(() => _index = safeIndex + 1),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Sonraki'),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuestionCard extends ConsumerWidget {
  const _QuestionCard({required this.question, this.onAnswered});
  final StudyQuestion question;
  final VoidCallback? onAnswered;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final answer =
        ref.watch(localProgressProvider).studyQuestionAnswers[question.id];
    final answered = answer != null;
    final tokens = AppThemeTokens.of(context);
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('${question.order}. ${question.stem}',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            ...question.options.map((option) {
              final picked = answer == option.letter;
              final correct = option.isCorrect;
              Color? color;
              if (answered && correct) color = Colors.green;
              if (answered && picked && !correct) color = Colors.red;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      minimumSize: const Size.fromHeight(48),
                      foregroundColor: color ?? tokens.primaryText,
                      side: color == null ? null : BorderSide(color: color),
                    ),
                    onPressed: answered
                        ? null
                        : () {
                            ref
                                .read(localProgressProvider.notifier)
                                .answerStudyQuestion(
                                  questionId: question.id,
                                  answer: option.letter,
                                  isCorrect: option.isCorrect,
                                  contentFingerprint:
                                      question.contentFingerprint,
                                );
                            onAnswered?.call();
                          },
                    child: Text('${option.letter}. ${option.text}',
                        textAlign: TextAlign.left),
                  ),
                ),
              );
            }),
            if (answered) ...<Widget>[
              const SizedBox(height: 8),
              _DetailBlock(label: 'Neden?', text: question.whyCorrect),
              _DetailBlock(label: 'Kanıt', text: question.evidence),
              _DetailBlock(label: 'Hatırlatma', text: question.reminderPattern),
              ...question.options
                  .where(
                      (item) => !item.isCorrect && item.explanation.isNotEmpty)
                  .map(
                    (item) => _DetailBlock(
                        label: '${item.letter} seçeneği',
                        text: item.explanation),
                  ),
            ],
          ]),
    );
  }
}

class _StudyReview extends StatelessWidget {
  const _StudyReview({required this.items});
  final List<StudyReviewItem> items;

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<StudyReviewItem>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.type, () => <StudyReviewItem>[]).add(item);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: grouped.entries
          .map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _reviewLabel(entry.key),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth >= 720
                          ? (constraints.maxWidth - 10) / 2
                          : constraints.maxWidth;
                      return Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: entry.value
                            .map(
                              (item) => SizedBox(
                                width: width,
                                child: _StudyReviewCard(item: item),
                              ),
                            )
                            .toList(growable: false),
                      );
                    },
                  ),
                ],
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _StudyReviewCard extends StatefulWidget {
  const _StudyReviewCard({required this.item});
  final StudyReviewItem item;

  @override
  State<_StudyReviewCard> createState() => _StudyReviewCardState();
}

class _StudyReviewCardState extends State<_StudyReviewCard> {
  bool _answerVisible = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isRecall =
        item.type == 'active_recall_en' || item.type == 'active_recall_tr';
    final usefulNote = isRecall ? '' : item.note;
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (item.promptEn.isNotEmpty)
            Text(item.promptEn, style: Theme.of(context).textTheme.titleSmall),
          if (item.promptTr.isNotEmpty) ...<Widget>[
            if (item.promptEn.isNotEmpty) const SizedBox(height: 4),
            Text(
              item.promptTr,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppThemeTokens.of(context).secondaryText),
            ),
          ],
          if (!isRecall &&
              (item.answerEn.isNotEmpty ||
                  item.answerTr.isNotEmpty)) ...<Widget>[
            const SizedBox(height: 7),
            if (item.answerEn.isNotEmpty)
              Text(
                item.answerEn,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            if (item.answerTr.isNotEmpty) ...<Widget>[
              if (item.answerEn.isNotEmpty) const SizedBox(height: 4),
              Text(
                item.answerTr,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppThemeTokens.of(context).secondaryText,
                    ),
              ),
            ],
          ],
          if (!isRecall && usefulNote.isNotEmpty)
            _DetailBlock(
              label: 'Not',
              text: usefulNote,
              textIsSecondary: true,
            ),
          if (isRecall &&
              (item.answerEn.isNotEmpty ||
                  item.answerTr.isNotEmpty)) ...<Widget>[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                minimumSize: const Size.fromHeight(40),
              ),
              onPressed: () => setState(() => _answerVisible = !_answerVisible),
              icon: Icon(_answerVisible
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined),
              label: Text(_answerVisible ? 'Cevabı gizle' : 'Cevabı göster'),
            ),
            if (_answerVisible) ...<Widget>[
              const SizedBox(height: 8),
              if (item.answerEn.isNotEmpty)
                Text(
                  item.answerEn,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              if (item.answerTr.isNotEmpty) ...<Widget>[
                if (item.answerEn.isNotEmpty) const SizedBox(height: 4),
                Text(
                  item.answerTr,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppThemeTokens.of(context).secondaryText,
                      ),
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }
}

String _wordItemLabel(String type) => switch (type) {
      'synonym' => 'Eş anlamlılar',
      'antonym' => 'Zıt anlamlılar',
      'family' => 'Kelime ailesi',
      'collocation' => 'Collocationlar',
      'pattern' => 'Kalıp / edat',
      _ => type,
    };

String _structureLabel(String category) => switch (category) {
      'connector' => 'Bağlaçlar',
      'yds_pattern' => 'YDS kalıp bankası',
      'collocation_bank' => 'Collocation bankası',
      'word_connection_map' => 'Kelime bağlantı haritası',
      'synonym_distinction' => 'Eş anlam ayrımları',
      _ => category,
    };

String _reviewLabel(String type) => switch (type) {
      'critical_word' => 'Kritik kelimeler',
      'critical_pattern' => 'Kritik kalıplar',
      'grammar_summary' => 'Gramer özeti',
      'yds_trap' => 'YDS tuzağı',
      'active_recall_en' => 'Aktif hatırlama · EN',
      'active_recall_tr' => 'Aktif hatırlama · TR',
      _ => type,
    };

String _bilingualText(String english, String turkish) {
  if (turkish.isEmpty || english == turkish) return english;
  return '$english ($turkish)';
}
