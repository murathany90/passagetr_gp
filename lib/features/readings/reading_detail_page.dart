import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme_tokens.dart';
import '../../core/content_providers.dart';
import '../../core/local_progress.dart';
import '../../models/content_models.dart';
import '../common/page_parts.dart';
import '../tts/student_tts_engine.dart';
import '../tts/student_tts_icon_button.dart';
import '../words/dictionary_detail_sheet.dart';
import '../words/word_detail_sheet.dart';
import 'reading_artwork.dart';
import 'reading_models.dart';

class ReadingDetailPage extends ConsumerWidget {
  const ReadingDetailPage({super.key, required this.readingId});

  final String readingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(readingDetailProvider(readingId));
    return detail.when(
      loading: () => const PageFrame(
        title: 'Okuma açılıyor',
        subtitle: 'Kaynak cümleler yükleniyor...',
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(48),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
      error: (error, _) => DataLoadErrorPage(
        message: error.toString(),
        onRetry: () => ref.invalidate(readingDetailProvider(readingId)),
      ),
      data: (item) => _ReadingDetailBody(detail: item),
    );
  }
}

class _ReadingDetailBody extends ConsumerStatefulWidget {
  const _ReadingDetailBody({required this.detail});

  final ReadingDetail detail;

  @override
  ConsumerState<_ReadingDetailBody> createState() => _ReadingDetailBodyState();
}

class _ReadingDetailBodyState extends ConsumerState<_ReadingDetailBody> {
  final Set<int> _revealedTranslationIndexes = <int>{};
  final Map<String, int> _answers = <String, int>{};
  var _showAllTranslations = false;
  var _showSummary = false;

  void _toggleTranslation(int index) {
    setState(() {
      if (_showAllTranslations) {
        _showAllTranslations = false;
        _revealedTranslationIndexes
          ..clear()
          ..addAll(widget.detail.sentences.map((sentence) => sentence.index))
          ..remove(index);
        return;
      }
      if (!_revealedTranslationIndexes.add(index)) {
        _revealedTranslationIndexes.remove(index);
      }
    });
  }

  void _showAllOrHideAll() {
    setState(() {
      if (_showAllTranslations) {
        _showAllTranslations = false;
        _revealedTranslationIndexes.clear();
      } else {
        _showAllTranslations = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    final passage = detail.passage;
    final tokens = AppThemeTokens.of(context);
    final tts = ref.watch(studentTtsControllerProvider);
    final progress = ref.watch(localProgressProvider);
    final completed = progress.completedReadingIds.contains(passage.id);
    final passageSpeaking = tts.isSpeaking &&
        tts.activeTarget == StudentTtsTarget.passage &&
        tts.activeReadingId == passage.id;
    final compact = MediaQuery.sizeOf(context).width < 620;
    return PageFrame(
      title: passage.displayTitle ?? passage.title,
      subtitle: _subtitleFor(passage),
      maxWidth: 920,
      actions: <Widget>[
        OutlinedButton.icon(
          onPressed: () => context.go('/readings'),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Okumalara dön'),
        ),
        FilledButton.icon(
          onPressed: detail.sentences.isEmpty
              ? null
              : () async {
                  final controller =
                      ref.read(studentTtsControllerProvider.notifier);
                  if (passageSpeaking) {
                    await controller.stop();
                    return;
                  }
                  await controller.playPassage(
                    readingId: passage.id,
                    segments: detail.sentences
                        .map((sentence) => StudentTtsPassageSegment(
                              sentenceIndex: sentence.index,
                              text: sentence.englishText,
                            ))
                        .toList(growable: false),
                  );
                },
          icon: Icon(
              passageSpeaking ? Icons.stop_rounded : Icons.volume_up_rounded),
          label: Text(passageSpeaking ? 'Durdur' : 'Tümünü dinle'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ReadingArtwork(
                  passage: passage,
                  height: compact ? 108 : 138,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: _metadata(passage, detail.sentences.length)
                        .map((label) => _Meta(
                              icon: label.icon,
                              label: label.value,
                            ))
                        .toList(growable: false),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 4, children: <Widget>[
            TextButton.icon(
              onPressed: _showAllOrHideAll,
              icon: Icon(_showAllTranslations
                  ? Icons.visibility_off_outlined
                  : Icons.translate_rounded),
              label: Text(_showAllTranslations
                  ? 'Tümünü gizle'
                  : 'Tüm çevirileri göster'),
            ),
          ]),
          const SizedBox(height: 16),
          const _WordLookupHint(),
          const SizedBox(height: 18),
          Text('Metin', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          if (detail.sentences.isEmpty)
            const SurfaceCard(
              child: Text(
                'Bu okuma kaydı için kaynak CSV’de İngilizce cümle bulunmuyor.',
              ),
            )
          else
            ...resolveArticleSections(detail.sentences).map(
              (section) => _SentenceCard(
                readingId: passage.id,
                section: section,
                showTranslation: _showAllTranslations ||
                    _revealedTranslationIndexes.contains(section.lookupIndex),
                onToggleTranslation: () =>
                    _toggleTranslation(section.lookupIndex),
              ),
            ),
          if (detail.focusWordIds.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text('Bu okumadaki önemli kelimeler',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            _FocusWords(wordIds: detail.focusWordIds),
          ],
          if (passage.summary != null) ...<Widget>[
            const SizedBox(height: 18),
            Text('Kısa Özet', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () => setState(() => _showSummary = !_showSummary),
              icon: Icon(_showSummary
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded),
              label: Text(_showSummary ? 'Özeti gizle' : 'Özeti göster'),
            ),
            if (_showSummary)
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(passage.summary!,
                        style: Theme.of(context).textTheme.bodyLarge),
                    if (passage.summaryTr case final summaryTr?
                        when summaryTr.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(summaryTr,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ],
                ),
              ),
          ],
          if (detail.questions.isNotEmpty) ...<Widget>[
            const SizedBox(height: 18),
            Text('Okuduğunu Anlama',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            ...detail.questions.map(
              (question) => _ComprehensionQuestion(
                question: question,
                selectedIndex: _answers[question.id],
                onSelected: (index) => setState(
                  () => _answers.putIfAbsent(question.id, () => index),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => ref
                .read(localProgressProvider.notifier)
                .toggleReadingCompleted(passage.id),
            icon: Icon(completed
                ? Icons.check_circle_rounded
                : Icons.check_circle_outline_rounded),
            label: Text(completed ? 'Okuma tamamlandı' : 'Okumayı tamamladım'),
          ),
          if (tts.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                tts.errorMessage!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: tokens.warning),
              ),
            ),
        ],
      ),
    );
  }
}

class _WordLookupHint extends StatelessWidget {
  const _WordLookupHint();

  @override
  Widget build(BuildContext context) => Row(children: <Widget>[
        const Icon(Icons.touch_app_outlined, size: 17),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            'Kelime anlamını görmek için İngilizce kelimeye dokunun.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ]);
}

class _SentenceCard extends ConsumerWidget {
  const _SentenceCard({
    required this.readingId,
    required this.section,
    required this.showTranslation,
    required this.onToggleTranslation,
  });

  final String readingId;
  final ReadingArticleSection section;
  final bool showTranslation;
  final VoidCallback onToggleTranslation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tts = ref.watch(studentTtsControllerProvider);
    final speaking = tts.isSpeaking &&
        tts.activeTarget == StudentTtsTarget.sentence &&
        tts.activeReadingId == readingId &&
        tts.activeSentenceIndex == section.lookupIndex;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SurfaceCard(
        key: ValueKey<String>('sentence-card-${section.lookupIndex}'),
        onTap: onToggleTranslation,
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${section.lookupIndex}',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _LookupableSentence(text: section.englishText),
                      if (showTranslation &&
                          section.turkishText != null) ...<Widget>[
                        const SizedBox(height: 9),
                        SelectableText(
                          section.turkishText!,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ]),
              ),
              StudentTtsIconButton(
                tooltip: 'İngilizce dinle',
                isSpeaking: speaking,
                isInitializing: tts.isInitializing &&
                    tts.activeReadingId == readingId &&
                    tts.activeSentenceIndex == section.lookupIndex,
                isUnavailable: tts.isUnavailable,
                onPlay: () => ref
                    .read(studentTtsControllerProvider.notifier)
                    .playSentence(
                      readingId: readingId,
                      sentenceIndex: section.lookupIndex,
                      text: section.englishText,
                    ),
                onStop: () =>
                    ref.read(studentTtsControllerProvider.notifier).stop(),
              ),
              if (section.turkishText != null)
                StudentTtsIconButton(
                  tooltip: 'Türkçe dinle',
                  isSpeaking: speaking,
                  isInitializing: tts.isInitializing &&
                      tts.activeReadingId == readingId &&
                      tts.activeSentenceIndex == section.lookupIndex,
                  isUnavailable: tts.isUnavailable,
                  onPlay: () => ref
                      .read(studentTtsControllerProvider.notifier)
                      .playTurkishSentence(
                        readingId: readingId,
                        sentenceIndex: section.lookupIndex,
                        text: section.turkishText!,
                      ),
                  onStop: () =>
                      ref.read(studentTtsControllerProvider.notifier).stop(),
                ),
            ]),
      ),
    );
  }
}

class _LookupableSentence extends ConsumerWidget {
  const _LookupableSentence({required this.text});

  final String text;

  Future<void> _showLookup(
    BuildContext context,
    WidgetRef ref,
    SentenceToken token,
  ) async {
    if (!token.isLookupable) return;
    final result =
        await ref.read(wordLookupServiceProvider).find(token.lookupQuery);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) {
        if (result.word case final word?) return WordDetailSheet(word: word);
        if (result.dictionaryEntries.isNotEmpty) {
          return DictionaryDetailSheet(entries: result.dictionaryEntries);
        }
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 32),
            child: Text(
              '“${token.displayWord}” için yerel içerikte sonuç bulunamadı.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = Theme.of(context).textTheme.bodyLarge;
    return Wrap(
      spacing: 3,
      runSpacing: 2,
      children: tokenizeSentence(text).map((token) {
        if (!token.isLookupable) return Text(token.displayWord, style: style);
        return Semantics(
          button: true,
          label: '${token.displayWord} sözlükte ara',
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => _showLookup(context, ref, token),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
              child: Text(token.displayWord, style: style),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }
}

class _FocusWords extends ConsumerWidget {
  const _FocusWords({required this.wordIds});

  final List<String> wordIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = ref.watch(wordsProvider);
    return words.when(
      loading: () => const SizedBox(
        height: 34,
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
              width: 20, height: 20, child: CircularProgressIndicator()),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (items) {
        final byId = <String, WordEntry>{
          for (final word in items) word.id: word
        };
        final focusWords = wordIds
            .map((identifier) => byId[identifier])
            .whereType<WordEntry>()
            .toList(growable: false);
        if (focusWords.isEmpty) return const SizedBox.shrink();
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: focusWords
              .map((word) => ActionChip(
                    label: Text(word.enWord),
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => WordDetailSheet(word: word),
                    ),
                  ))
              .toList(growable: false),
        );
      },
    );
  }
}

class _ComprehensionQuestion extends StatelessWidget {
  const _ComprehensionQuestion({
    required this.question,
    required this.selectedIndex,
    required this.onSelected,
  });

  final ReadingQuestion question;
  final int? selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final answered = selectedIndex != null;
    final correct = selectedIndex == question.correctOptionIndex;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SurfaceCard(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('${question.sortOrder}. ${question.question}',
                  style: Theme.of(context).textTheme.titleMedium),
              if (question.questionTr case final questionTr?
                  when questionTr.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(questionTr, style: Theme.of(context).textTheme.bodyMedium),
              ],
              const SizedBox(height: 10),
              for (var index = 0; index < question.options.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: OutlinedButton(
                    onPressed: answered ? null : () => onSelected(index),
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      foregroundColor:
                          answered && index == question.correctOptionIndex
                              ? Colors.green
                              : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(question.options[index]),
                        if (index < question.optionsTr.length &&
                            question.optionsTr[index].isNotEmpty) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(question.optionsTr[index],
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ],
                    ),
                  ),
                ),
              if (answered) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  correct ? 'Doğru.' : 'Henüz değil.',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: correct
                            ? Colors.green
                            : Theme.of(context).colorScheme.error,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                    'Doğru cevap: ${question.answerEn ?? question.options[question.correctOptionIndex]}'),
                if (question.answerTr case final answerTr?
                    when answerTr.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(answerTr, style: Theme.of(context).textTheme.bodySmall),
                ],
                if (question.explanation != null) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(question.explanation!,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
                if (question.explanationTr case final explanationTr?
                    when explanationTr.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(explanationTr,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ]),
      ),
    );
  }
}

class _MetaValue {
  const _MetaValue(this.icon, this.value);

  final IconData icon;
  final String value;
}

List<_MetaValue> _metadata(ReadingPassage passage, int sentenceCount) {
  final values = <_MetaValue>[
    _MetaValue(Icons.format_list_numbered_rounded, '$sentenceCount cümle'),
  ];
  if (passage.wordCount > 0) {
    values.add(
        _MetaValue(Icons.text_fields_rounded, '${passage.wordCount} kelime'));
  }
  if (passage.estimatedReadingMinutes > 0) {
    values.add(_MetaValue(
        Icons.schedule_rounded, '~${passage.estimatedReadingMinutes} dk'));
  }
  if (passage.level != null) {
    values.add(_MetaValue(Icons.speed_rounded, passage.level!));
  }
  if (passage.category != null) {
    values.add(_MetaValue(Icons.category_outlined, passage.category!));
  }
  return values;
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Icon(icon, size: 17),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]);
}

String _subtitleFor(ReadingPassage passage) {
  if (passage.turkishTitle case final title? when title.isNotEmpty) {
    return title;
  }
  return [passage.category, passage.level]
          .whereType<String>()
          .where((part) => part.isNotEmpty)
          .join(' · ')
          .isEmpty
      ? 'Kaynak cümlelerle okuma pratiği'
      : [passage.category, passage.level]
          .whereType<String>()
          .where((part) => part.isNotEmpty)
          .join(' · ');
}
