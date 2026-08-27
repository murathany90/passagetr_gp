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
import 'reading_artwork.dart';
import 'reading_models.dart';
import '../words/dictionary_detail_sheet.dart';
import '../words/word_detail_sheet.dart';

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
                  child: CircularProgressIndicator()))),
      error: (error, _) => DataLoadErrorPage(
          message: error.toString(),
          onRetry: () => ref.invalidate(readingDetailProvider(readingId))),
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
  bool _showTranslations = true;

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
    return PageFrame(
      title: passage.title,
      subtitle: _subtitleFor(passage),
      maxWidth: 920,
      actions: <Widget>[
        OutlinedButton.icon(
            onPressed: () => context.go('/readings'),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Okumalara dön')),
        FilledButton.icon(
          onPressed: () async {
            final controller = ref.read(studentTtsControllerProvider.notifier);
            if (passageSpeaking) {
              await controller.stop();
              return;
            }
            await controller.playPassage(
                readingId: passage.id,
                segments: detail.sentences
                    .map((sentence) => StudentTtsPassageSegment(
                        sentenceIndex: sentence.index,
                        text: sentence.englishText))
                    .toList(growable: false));
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
                          height: 210,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(24))),
                      Padding(
                          padding: const EdgeInsets.all(20),
                          child: Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: <Widget>[
                                _Meta(
                                    icon: Icons.format_list_numbered_rounded,
                                    label: '${detail.sentences.length} cümle'),
                                if (passage.level != null)
                                  _Meta(
                                      icon: Icons.speed_rounded,
                                      label: passage.level!),
                                if (passage.category != null)
                                  _Meta(
                                      icon: Icons.category_outlined,
                                      label: passage.category!),
                              ])),
                    ])),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 4, children: <Widget>[
              TextButton.icon(
                onPressed: () =>
                    setState(() => _showTranslations = !_showTranslations),
                icon: Icon(_showTranslations
                    ? Icons.translate_rounded
                    : Icons.visibility_outlined),
                label: Text(_showTranslations ? 'TR gizle' : 'TR göster'),
              ),
              TextButton.icon(
                onPressed: () => ref
                    .read(localProgressProvider.notifier)
                    .toggleReadingCompleted(passage.id),
                icon: Icon(completed
                    ? Icons.check_circle_rounded
                    : Icons.check_circle_outline_rounded),
                label: Text(completed ? 'Tamamlandı' : 'Tamamlandı say'),
              ),
            ]),
            const SizedBox(height: 20),
            if (passage.summary != null) ...<Widget>[
              Text(passage.summary!,
                  style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 20)
            ],
            Text('Metin', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            ...resolveArticleSections(detail.sentences)
                .map((section) => _SentenceCard(
                      readingId: passage.id,
                      section: section,
                      showTranslation: _showTranslations,
                    )),
            if (tts.errorMessage != null)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(tts.errorMessage!,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: tokens.warning))),
          ]),
    );
  }
}

class _SentenceCard extends ConsumerWidget {
  const _SentenceCard({
    required this.readingId,
    required this.section,
    required this.showTranslation,
  });
  final String readingId;
  final ReadingArticleSection section;
  final bool showTranslation;
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
                    borderRadius: BorderRadius.circular(10)),
                child: Text('${section.lookupIndex}',
                    style: Theme.of(context).textTheme.bodySmall)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                  _LookupableSentence(text: section.englishText),
                  if (showTranslation &&
                      section.turkishText != null) ...<Widget>[
                    const SizedBox(height: 9),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: SelectableText(
                            section.turkishText!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
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
                          onStop: () => ref
                              .read(studentTtsControllerProvider.notifier)
                              .stop(),
                        ),
                      ],
                    ),
                  ],
                ])),
            StudentTtsIconButton(
              isSpeaking: speaking,
              isInitializing: tts.isInitializing &&
                  tts.activeReadingId == readingId &&
                  tts.activeSentenceIndex == section.lookupIndex,
              isUnavailable: tts.isUnavailable,
              onPlay: () async {
                await ref
                    .read(studentTtsControllerProvider.notifier)
                    .playSentence(
                        readingId: readingId,
                        sentenceIndex: section.lookupIndex,
                        text: section.englishText);
              },
              onStop: () async {
                await ref.read(studentTtsControllerProvider.notifier).stop();
              },
            ),
          ])),
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
    if (!token.isLookupable) {
      return;
    }
    final result =
        await ref.read(wordLookupServiceProvider).find(token.lookupQuery);
    if (!context.mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) {
        if (result.word case final word?) {
          return WordDetailSheet(word: word);
        }
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
        if (!token.isLookupable) {
          return Text(token.displayWord, style: style);
        }
        return Semantics(
          button: true,
          label: '${token.displayWord} sözlükte ara',
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => _showLookup(context, ref, token),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
              child: Text(
                token.displayWord,
                style: style?.copyWith(
                  decoration: TextDecoration.underline,
                  decorationColor: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: .42),
                ),
              ),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }
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
        Text(label, style: Theme.of(context).textTheme.bodySmall)
      ]);
}

String _subtitleFor(ReadingPassage passage) => [passage.category, passage.level]
        .whereType<String>()
        .where((part) => part.isNotEmpty)
        .join(' · ')
        .isEmpty
    ? 'Kaynak cümlelerle okuma pratiği'
    : [passage.category, passage.level]
        .whereType<String>()
        .where((part) => part.isNotEmpty)
        .join(' · ');
