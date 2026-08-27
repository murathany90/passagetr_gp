import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme_tokens.dart';
import '../../core/content_providers.dart';
import '../../models/content_models.dart';
import '../tts/student_tts_icon_button.dart';

class DictionaryDetailSheet extends ConsumerWidget {
  const DictionaryDetailSheet({super.key, required this.entry});

  final DictionaryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppThemeTokens.of(context);
    final tts = ref.watch(studentTtsControllerProvider);
    final speaking = tts.isSpeaking && tts.activeWordId == entry.id;
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
                          entry.enWord,
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                        if (entry.pos case final pos?) ...<Widget>[
                          const SizedBox(height: 6),
                          Text(
                            pos,
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
                        tts.isInitializing && tts.activeWordId == entry.id,
                    isUnavailable: tts.isUnavailable,
                    onPlay: () => ref
                        .read(studentTtsControllerProvider.notifier)
                        .playDictionaryEntry(
                            entryId: entry.id, text: entry.enWord),
                    onStop: () =>
                        ref.read(studentTtsControllerProvider.notifier).stop(),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'TÜRKÇE ANLAMI',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(letterSpacing: 1),
              ),
              const SizedBox(height: 5),
              Text(entry.trMeaning,
                  style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      ),
    );
  }
}
