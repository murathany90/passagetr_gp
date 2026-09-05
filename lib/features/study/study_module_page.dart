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
        final tokens = AppThemeTokens.of(context);
        final progress = ref.watch(localProgressProvider);
        final sectionDone = progress.completedStudySectionKeys.contains(
          '${module.module.id}:${_section.storageValue}',
        );
        return PageFrame(
          title: 'Modül ${module.module.number}',
          subtitle: '${module.module.mainTopic} · ${module.module.subtopic}',
          actions: <Widget>[
            TextButton.icon(
              onPressed: () => _setSection(_StudySection.words),
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Başa dön'),
            ),
          ],
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SurfaceCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(module.module.grammarFocus,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 5),
                        Text(module.module.levelProfile),
                      ]),
                ),
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _sections
                        .map((item) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(item.label),
                                selected: item == _section,
                                selectedColor: tokens.accent,
                                labelStyle: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: item == _section
                                      ? Colors.white
                                      : tokens.primaryText,
                                ),
                                onSelected: (_) => _setSection(item),
                              ),
                            ))
                        .toList(growable: false),
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
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
                        sectionDone ? 'Bölüm tamamlandı' : 'Bölümü tamamla'),
                  ),
                ),
                const SizedBox(height: 16),
                _section.build(module),
              ]),
        );
      },
    );
  }
}

enum _StudySection {
  words('Kelime', 'words'),
  sentences('Cümle & Gramer', 'sentences'),
  reading('Reading', 'reading'),
  translations('Çeviri', 'translations'),
  structures('YDS Yapıları', 'structures'),
  test('Test', 'test'),
  review('Review', 'review');

  const _StudySection(this.label, this.storageValue);
  final String label;
  final String storageValue;

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
                child: _StudyWordCard(word: word),
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
    final canonicalWords = ref.watch(wordsProvider).maybeWhen(
          data: (items) => items,
          orElse: () => const <WordEntry>[],
        );
    WordEntry? canonicalWord;
    for (final item in canonicalWords) {
      if (item.enWord.toLowerCase() == word.wordRef.toLowerCase()) {
        canonicalWord = item;
        break;
      }
    }
    final speaking = tts.isSpeaking && tts.activeWordId == word.id;
    final grouped = <String, List<StudyWordItem>>{};
    for (final item in word.items) {
      grouped.putIfAbsent(item.type, () => <StudyWordItem>[]).add(item);
    }
    return SurfaceCard(
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
                        if (canonicalWord == null)
                          Text('${word.order}. ${word.headword}',
                              style: Theme.of(context).textTheme.titleLarge)
                        else
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              alignment: Alignment.centerLeft,
                            ),
                            onPressed: () => showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              builder: (_) => WordDetailSheet(
                                word: canonicalWord!,
                              ),
                            ),
                            child: Text('${word.order}. ${word.headword}',
                                style: Theme.of(context).textTheme.titleLarge),
                          ),
                        const SizedBox(height: 4),
                        Text('${word.meaningTr} · ${word.pos} · ${word.level}'),
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
                    onStop: () =>
                        ref.read(studentTtsControllerProvider.notifier).stop(),
                  ),
                ]),
            const SizedBox(height: 10),
            Text(word.contextMeaning),
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
              _DetailBlock(label: 'YDS notu', text: word.ydsNote),
              _DetailBlock(
                  label: 'Örnek',
                  text: word.exampleEn,
                  secondary: word.exampleTr),
              ...grouped.entries.map((entry) => _WordItemsBlock(
                    label: _wordItemLabel(entry.key),
                    items: entry.value,
                  )),
            ],
          ]),
    );
  }
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({required this.label, required this.text, this.secondary});
  final String label;
  final String text;
  final String? secondary;
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
            if (text.isNotEmpty) Text(text),
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              ...items.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text([
                      if (item.subtype.isNotEmpty) '${item.subtype}:',
                      if (item.valueEn.isNotEmpty) item.valueEn,
                      if (item.valueTr.isNotEmpty) '— ${item.valueTr}',
                      if (item.usageNote.isNotEmpty) '(${item.usageNote})',
                    ].join(' ')),
                  )),
            ]),
      );
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
          child: SurfaceCard(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('${sentence.order}. ${sentence.english}',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 6, children: <Widget>[
                    Chip(label: Text(sentence.level)),
                    TextButton.icon(
                      onPressed: () => setState(() => showTr
                          ? _translations.remove(sentence.order)
                          : _translations.add(sentence.order)),
                      icon: const Icon(Icons.translate_rounded),
                      label:
                          Text(showTr ? 'Çeviriyi gizle' : 'Çeviriyi göster'),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() => showAnalysis
                          ? _analysis.remove(sentence.order)
                          : _analysis.add(sentence.order)),
                      icon: const Icon(Icons.account_tree_outlined),
                      label:
                          Text(showAnalysis ? 'Analizi gizle' : 'Analizi aç'),
                    ),
                  ]),
                  if (showTr) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(sentence.turkish)
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
        );
      }).toList(growable: false));
}

class _AnalysisTile extends StatelessWidget {
  const _AnalysisTile({required this.label, required this.text});
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
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
            Text(text),
          ]),
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
        SurfaceCard(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                    widget.reading.title.isEmpty
                        ? widget.fallbackTitle
                        : widget.reading.title,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 14),
                _HighlightedReading(
                  text: widget.reading.textEn,
                  words: widget.targetWords,
                ),
              ]),
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
                      child: _AnalysisTile(label: item.$1, text: item.$2),
                    ))
                .toList(growable: false),
          );
        },
      );
}

class _HighlightedReading extends StatelessWidget {
  const _HighlightedReading({required this.text, required this.words});
  final String text;
  final List<StudyWord> words;
  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final expressions =
        words.map((word) => RegExp.escape(word.headword)).join('|');
    if (expressions.isEmpty) return SelectableText(text);
    final matches =
        RegExp('\\b($expressions)\\b', caseSensitive: false).allMatches(text);
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      spans.add(TextSpan(
        text: text.substring(match.start, match.end),
        style: TextStyle(
          color: tokens.accent,
          fontWeight: FontWeight.w700,
          backgroundColor: tokens.accent.withValues(alpha: .08),
        ),
      ));
      cursor = match.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return SelectableText.rich(TextSpan(
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
    final list = _enTr ? widget.translations.enTr : widget.translations.trEn;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(spacing: 8, children: <Widget>[
            ChoiceChip(
                label: const Text('EN → TR'),
                selected: _enTr,
                onSelected: (_) => setState(() => _enTr = true)),
            ChoiceChip(
                label: const Text('TR → EN'),
                selected: !_enTr,
                onSelected: (_) => setState(() => _enTr = false)),
          ]),
          const SizedBox(height: 12),
          ...list.map((item) {
            final key = (_enTr ? 100 : 200) + item.order;
            final revealed = _revealed.contains(key);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SurfaceCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('${item.order}. ${item.source}',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => setState(() => revealed
                            ? _revealed.remove(key)
                            : _revealed.add(key)),
                        icon: Icon(revealed
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        label:
                            Text(revealed ? 'Cevabı gizle' : 'Cevabı göster'),
                      ),
                      if (revealed) ...<Widget>[
                        const SizedBox(height: 10),
                        _DetailBlock(
                            label: 'Önerilen çeviri', text: item.answer),
                        _DetailBlock(
                            label: 'Alternatif', text: item.alternative),
                        _DetailBlock(label: 'İskelet', text: item.skeleton),
                        _DetailBlock(
                            label: 'Anahtar kelimeler', text: item.keyWords),
                        _DetailBlock(
                            label: 'Gramer notu', text: item.grammarNote),
                        _DetailBlock(label: 'Çeviri mantığı', text: item.logic),
                      ],
                    ]),
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
              padding: const EdgeInsets.only(bottom: 18),
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
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(item.expression, style: Theme.of(context).textTheme.titleSmall),
          if (item.meaningTr.isNotEmpty) ...<Widget>[
            const SizedBox(height: 5),
            Text(item.meaningTr),
          ],
          if (item.pattern.isNotEmpty)
            _DetailBlock(label: 'Pattern', text: item.pattern),
          if (item.example.isNotEmpty)
            _DetailBlock(label: 'Örnek', text: item.example),
          if (hasDetails) ...<Widget>[
            const SizedBox(height: 8),
            TextButton.icon(
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
              padding: const EdgeInsets.only(bottom: 18),
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
    final prompt = <String>[item.promptEn, item.promptTr]
        .where((value) => value.isNotEmpty)
        .join('\n');
    final answer = <String>[item.answerEn, item.answerTr]
        .where((value) => value.isNotEmpty)
        .join('\n');
    final usefulNote =
        item.note.contains('Kaynak cevapta gösterilmiyor') ? '' : item.note;
    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (prompt.isNotEmpty)
            Text(prompt, style: Theme.of(context).textTheme.titleSmall),
          if (!isRecall && answer.isNotEmpty) ...<Widget>[
            const SizedBox(height: 7),
            Text(answer),
          ],
          if (!isRecall && usefulNote.isNotEmpty)
            _DetailBlock(label: 'Not', text: usefulNote),
          if (isRecall && answer.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => setState(() => _answerVisible = !_answerVisible),
              icon: Icon(_answerVisible
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined),
              label: Text(_answerVisible ? 'Cevabı gizle' : 'Cevabı göster'),
            ),
            if (_answerVisible) ...<Widget>[
              const SizedBox(height: 8),
              Text(answer),
            ],
          ],
          if (isRecall && answer.isEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'Kendin hatırla',
              style: TextStyle(color: AppThemeTokens.of(context).secondaryText),
            ),
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
