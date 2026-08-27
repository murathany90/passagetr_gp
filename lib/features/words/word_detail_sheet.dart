import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme_tokens.dart';
import '../../core/content_providers.dart';
import '../../core/local_progress.dart';
import '../../models/content_models.dart';
import '../tts/student_tts_icon_button.dart';

class WordDetailSheet extends ConsumerWidget {
  const WordDetailSheet({super.key, required this.word});

  final WordEntry word;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppThemeTokens.of(context);
    final tts = ref.watch(studentTtsControllerProvider);
    final progress = ref.watch(localProgressProvider);
    final speaking = tts.isSpeaking && tts.activeWordId == word.id;
    final favorite = progress.favoriteWordIds.contains(word.id);
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
                          borderRadius: BorderRadius.circular(8)))),
              const SizedBox(height: 22),
              Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                          Text(word.enWord,
                              style: Theme.of(context).textTheme.displaySmall),
                          const SizedBox(height: 6),
                          Text(word.pos,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(color: tokens.hero)),
                        ])),
                    StudentTtsIconButton(
                      iconSize: 26,
                      isSpeaking: speaking,
                      isInitializing:
                          tts.isInitializing && tts.activeWordId == word.id,
                      isUnavailable: tts.isUnavailable,
                      onPlay: () async {
                        await ref
                            .read(studentTtsControllerProvider.notifier)
                            .playWord(word: word);
                      },
                      onStop: () async {
                        await ref
                            .read(studentTtsControllerProvider.notifier)
                            .stop();
                      },
                    ),
                    IconButton(
                      tooltip:
                          favorite ? 'Favorilerden çıkar' : 'Favoriye ekle',
                      onPressed: () => ref
                          .read(localProgressProvider.notifier)
                          .toggleFavoriteWord(word.id),
                      icon: Icon(favorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded),
                      color: favorite ? tokens.hero : null,
                    ),
                  ]),
              const SizedBox(height: 20),
              _DetailBlock(label: 'Türkçe anlamı', value: word.trMeaning),
              _DetailBlock(label: 'Örnek', value: word.exampleEn),
              if (_notBlank(word.exampleTr))
                _DetailBlock(label: 'Örnek çevirisi', value: word.exampleTr!),
              if (_notBlank(word.synonymsRaw))
                _DetailBlock(label: 'Eş anlamlılar', value: word.synonymsRaw!),
              if (_notBlank(word.antonymsRaw))
                _DetailBlock(label: 'Zıt anlamlılar', value: word.antonymsRaw!),
              if (_notBlank(word.notes))
                _DetailBlock(label: 'Not', value: word.notes!),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.go(
                        '/dictionary?q=${Uri.encodeQueryComponent(word.enWord)}');
                  },
                  icon: const Icon(Icons.translate_outlined),
                  label: const Text('Sözlükte daha fazla anlam'),
                ),
              ),
              if (tts.errorMessage != null)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(tts.errorMessage!,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: tokens.warning))),
            ])),
      ),
    );
  }
}

bool _notBlank(String? value) => value?.trim().isNotEmpty ?? false;

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 17),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label.toUpperCase(),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(letterSpacing: 1)),
              const SizedBox(height: 5),
              Text(value, style: Theme.of(context).textTheme.bodyLarge),
            ]),
      );
}
