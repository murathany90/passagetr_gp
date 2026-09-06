import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme_tokens.dart';
import '../../core/content_providers.dart';
import '../../core/local_progress.dart';
import '../../models/study_models.dart';
import '../tts/student_tts_icon_button.dart';

/// The vetted 02_Words / 03_Word_Items detail shown only when the Study
/// headword has no exact entry in the shared 7,500-word canonical bank.
class StudyWordDetailSheet extends ConsumerWidget {
  const StudyWordDetailSheet({super.key, required this.word});

  final StudyWord word;

  String get _favoriteId => 'study-word:${word.id}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppThemeTokens.of(context);
    final tts = ref.watch(studentTtsControllerProvider);
    final progress = ref.watch(localProgressProvider);
    final favorite = progress.favoriteWordIds.contains(_favoriteId);
    final speaking = tts.isSpeaking && tts.activeWordId == word.id;
    final grouped = <String, List<StudyWordItem>>{};
    for (final item in word.items) {
      grouped.putIfAbsent(item.type, () => <StudyWordItem>[]).add(item);
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Align(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: tokens.surfaceBorder,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          word.headword,
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                        if (word.pos.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 6),
                          Text(
                            word.pos,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: tokens.hero),
                          ),
                        ],
                      ],
                    ),
                  ),
                  StudentTtsIconButton(
                    iconSize: 26,
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
                  IconButton(
                    tooltip: favorite ? 'Favorilerden çıkar' : 'Favoriye ekle',
                    onPressed: () => ref
                        .read(localProgressProvider.notifier)
                        .toggleFavoriteWord(_favoriteId),
                    icon: Icon(
                      favorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                    ),
                    color: favorite ? tokens.hero : null,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _StudyWordDetailBlock(
                  label: 'Türkçe anlamı', value: word.meaningTr),
              _StudyWordDetailBlock(
                label: 'Bağlam anlamı',
                value: word.contextMeaning,
              ),
              _StudyWordDetailBlock(label: 'YDS notu', value: word.ydsNote),
              _StudyWordDetailBlock(
                label: 'Örnek',
                value: word.exampleEn,
                emphasized: true,
              ),
              _StudyWordDetailBlock(
                label: 'Örnek çevirisi',
                value: word.exampleTr,
              ),
              ...grouped.entries.map(
                (entry) => _StudyWordItemsBlock(
                  label: _studyWordItemLabel(entry.key),
                  items: entry.value,
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: () => ref
                        .read(localProgressProvider.notifier)
                        .toggleFavoriteWord(_favoriteId),
                    icon: Icon(
                      favorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                    ),
                    label: Text(
                      favorite ? 'Favorilerden çıkar' : 'Favoriye ekle',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.go(
                        '/dictionary?q=${Uri.encodeQueryComponent(word.headword)}',
                      );
                    },
                    icon: const Icon(Icons.translate_outlined),
                    label: const Text('Sözlükte aç'),
                  ),
                ],
              ),
              if (tts.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
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
        ),
      ),
    );
  }
}

class _StudyWordDetailBlock extends StatelessWidget {
  const _StudyWordDetailBlock({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(letterSpacing: 1),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: emphasized ? FontWeight.w700 : null,
                ),
          ),
        ],
      ),
    );
  }
}

class _StudyWordItemsBlock extends StatelessWidget {
  const _StudyWordItemsBlock({required this.label, required this.items});

  final String label;
  final List<StudyWordItem> items;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(letterSpacing: 1),
          ),
          const SizedBox(height: 5),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
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
            ),
          ),
        ],
      ),
    );
  }
}

String _studyWordItemLabel(String type) => switch (type) {
      'collocation' => 'Kalıplar',
      'synonym' => 'Eş anlamlılar',
      'antonym' => 'Zıt anlamlılar',
      'family' => 'Kelime ailesi',
      _ => type.isEmpty ? 'Ek bilgi' : type,
    };
