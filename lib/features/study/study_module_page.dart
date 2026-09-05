import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/content_providers.dart';
import '../../core/local_progress.dart';
import '../../core/app_theme_tokens.dart';
import '../../models/study_models.dart';
import '../common/page_parts.dart';
import '../tts/student_tts_icon_button.dart';

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
      data: (module) => PageFrame(
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
                              onSelected: (_) => _setSection(item),
                            ),
                          ))
                      .toList(growable: false),
                ),
              ),
              const SizedBox(height: 16),
              _section.build(module),
            ]),
      ),
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
                        Text('${word.order}. ${word.headword}',
                            style: Theme.of(context).textTheme.titleLarge),
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
                          child:
                              _DetailBlock(label: entry.key, text: entry.value),
                        )),
                  ],
                ]),
          ),
        );
      }).toList(growable: false));
}

class _StudyReading extends StatelessWidget {
  const _StudyReading({
    required this.reading,
    required this.fallbackTitle,
    required this.targetWords,
  });
  final StudyReading reading;
  final String fallbackTitle;
  final List<StudyWord> targetWords;

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        SurfaceCard(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(reading.title.isEmpty ? fallbackTitle : reading.title,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 14),
                _HighlightedReading(text: reading.textEn, words: targetWords),
              ]),
        ),
        const SizedBox(height: 12),
        SurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _DetailBlock(label: 'Ana fikir', text: reading.mainIdeaTr),
                _DetailBlock(label: 'Akış', text: reading.flowAnalysis),
                _DetailBlock(
                    label: 'Önemli kelimeler', text: reading.importantWords),
                _DetailBlock(label: 'Bağlaçlar', text: reading.connectorMap),
                _DetailBlock(
                    label: 'Referanslar', text: reading.referenceAnalysis),
              ]),
        ),
        const SizedBox(height: 16),
        Text('Reading soruları',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...reading.questions.map((question) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _QuestionCard(question: question),
            )),
      ]);
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
            .map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: SurfaceCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(_structureLabel(entry.key),
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          ...entry.value.map((item) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(item.expression,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall),
                                      if (item.meaningTr.isNotEmpty)
                                        Text(item.meaningTr),
                                      if (item.pattern.isNotEmpty)
                                        Text(item.pattern),
                                      if (item.example.isNotEmpty)
                                        Text(item.example),
                                      if (item.confusionNote.isNotEmpty)
                                        Text(item.confusionNote),
                                      if (item.relatedWords.isNotEmpty)
                                        Text(item.relatedWords),
                                      if (item.note.isNotEmpty) Text(item.note),
                                    ]),
                              )),
                        ]),
                  ),
                ))
            .toList(growable: false));
  }
}

class _StudyTest extends ConsumerWidget {
  const _StudyTest({required this.moduleId, required this.questions});
  final String moduleId;
  final List<StudyQuestion> questions;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final answers = ref.watch(localProgressProvider).studyQuestionAnswers;
    final answered =
        questions.where((item) => answers.containsKey(item.id)).length;
    final correct = questions
        .where((item) => answers[item.id] == item.correctOption)
        .length;
    final complete = answered == questions.length;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SurfaceCard(
            padding: const EdgeInsets.all(16),
            child: Text(complete
                ? 'Sonuç: $correct / ${questions.length}'
                : '$answered / ${questions.length} cevaplandı'),
          ),
          const SizedBox(height: 12),
          ...questions.map((question) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _QuestionCard(
                  question: question,
                  onAnswered: () {
                    final state = ref.read(localProgressProvider);
                    if (questions.every((item) =>
                        state.studyQuestionAnswers.containsKey(item.id))) {
                      ref
                          .read(localProgressProvider.notifier)
                          .markStudyModuleCompleted(moduleId);
                    }
                  },
                ),
              )),
        ]);
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
            .map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SurfaceCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(_reviewLabel(entry.key),
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          ...entry.value.map((item) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      if (item.promptEn.isNotEmpty)
                                        Text(item.promptEn),
                                      if (item.promptTr.isNotEmpty)
                                        Text(item.promptTr),
                                      if (item.answerEn.isNotEmpty ||
                                          item.answerTr.isNotEmpty)
                                        Text([item.answerEn, item.answerTr]
                                            .where((value) => value.isNotEmpty)
                                            .join(' — ')),
                                      if (item.note.isNotEmpty) Text(item.note),
                                    ]),
                              )),
                        ]),
                  ),
                ))
            .toList(growable: false));
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
