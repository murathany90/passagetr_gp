import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme_tokens.dart';
import '../../core/content_providers.dart';
import '../../models/content_models.dart';
import '../tts/student_tts_icon_button.dart';

class DictionaryDetailSheet extends ConsumerWidget {
  const DictionaryDetailSheet({super.key, required this.entries})
      : assert(entries.length > 0);

  final List<DictionaryEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final first = entries.first;
    final tokens = AppThemeTokens.of(context);
    final tts = ref.watch(studentTtsControllerProvider);
    final speaking = tts.isSpeaking && tts.activeWordId == first.id;
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
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(first.enWord,
                            style: Theme.of(context).textTheme.displaySmall),
                        const SizedBox(height: 5),
                        Text(
                          entries.length == 1
                              ? 'Sözlük anlamı'
                              : '${entries.length} farklı anlam',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: tokens.hero),
                        ),
                      ],
                    ),
                  ),
                  StudentTtsIconButton(
                    iconSize: 26,
                    isSpeaking: speaking,
                    isInitializing:
                        tts.isInitializing && tts.activeWordId == first.id,
                    isUnavailable: tts.isUnavailable,
                    onPlay: () => ref
                        .read(studentTtsControllerProvider.notifier)
                        .playDictionaryEntry(
                            entryId: first.id, text: first.enWord),
                    onStop: () =>
                        ref.read(studentTtsControllerProvider.notifier).stop(),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              for (var index = 0; index < entries.length; index++)
                _DictionaryMeaning(
                  index: index,
                  entry: entries[index],
                  isLast: index == entries.length - 1,
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.go(
                      '/dictionary?q=${Uri.encodeQueryComponent(first.enWord)}');
                },
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Sözlükte aç'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DictionaryMeaning extends StatelessWidget {
  const _DictionaryMeaning({
    required this.index,
    required this.entry,
    required this.isLast,
  });

  final int index;
  final DictionaryEntry entry;
  final bool isLast;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('${index + 1}.',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (entry.pos case final pos?)
                      Text(pos,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontWeight: FontWeight.w800)),
                    Text(entry.trMeaning,
                        style: Theme.of(context).textTheme.bodyLarge),
                  ],
                ),
              ),
            ]),
      );
}
