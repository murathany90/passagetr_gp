import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme_tokens.dart';
import '../../core/content_providers.dart';
import '../../models/content_models.dart';
import '../common/page_parts.dart';
import 'word_detail_sheet.dart';

class FlashcardsPage extends ConsumerStatefulWidget {
  const FlashcardsPage({super.key, this.packId});
  final String? packId;
  @override
  ConsumerState<FlashcardsPage> createState() => _FlashcardsPageState();
}

class _FlashcardsPageState extends ConsumerState<FlashcardsPage> {
  late final PageController _controller;
  int _index = 0;
  int _known = 0;
  int _review = 0;
  bool _showMeaning = false;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final words = ref.watch(wordsProvider);
    return words.when(
      loading: () => const PageFrame(
          title: 'Flashcard',
          subtitle: 'Kartlar hazırlanıyor...',
          child: Center(child: CircularProgressIndicator())),
      error: (error, _) => DataLoadErrorPage(
          message: error.toString(),
          onRetry: () => ref.invalidate(wordsProvider)),
      data: (allWords) {
        final words = _selectCards(allWords, widget.packId);
        if (words.isEmpty) {
          return const DataLoadErrorPage(
              message: 'DATA_LOAD_ERROR: Bu paket için kelime bulunamadı.');
        }
        return PageFrame(
          title: 'Flashcard',
          subtitle:
              '${_index + 1} / ${words.length} · Bu oturum: $_known bildim, $_review tekrar',
          actions: <Widget>[
            OutlinedButton.icon(
                onPressed: () => context.go('/words'),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Kelimelere dön'))
          ],
          child: Column(children: <Widget>[
            LinearProgressIndicator(
                value: (_index + 1) / words.length,
                minHeight: 7,
                borderRadius: BorderRadius.circular(8)),
            const SizedBox(height: 26),
            SizedBox(
              height: 330,
              child: PageView.builder(
                controller: _controller,
                itemCount: words.length,
                onPageChanged: (value) => setState(() {
                  _index = value;
                  _showMeaning = false;
                }),
                itemBuilder: (context, index) => _Flashcard(
                    word: words[index],
                    showMeaning: index == _index && _showMeaning,
                    onFlip: () => setState(() => _showMeaning = !_showMeaning),
                    onDetail: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => WordDetailSheet(word: words[index]))),
              ),
            ),
            const SizedBox(height: 20),
            Row(children: <Widget>[
              Expanded(
                  child: OutlinedButton.icon(
                      onPressed: _index == 0
                          ? null
                          : () => _controller.previousPage(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOut),
                      icon: const Icon(Icons.chevron_left_rounded),
                      label: const Text('Önceki'))),
              const SizedBox(width: 12),
              Expanded(
                  child: FilledButton.icon(
                      onPressed: () => _record(false, words.length),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Tekrar'))),
              const SizedBox(width: 12),
              Expanded(
                  child: FilledButton.icon(
                      onPressed: () => _record(true, words.length),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Bildim'))),
            ]),
            const SizedBox(height: 14),
            Text('İlerleme yalnızca bu açık oturumda tutulur.',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
        );
      },
    );
  }

  void _record(bool known, int length) {
    setState(() {
      if (known) {
        _known++;
      } else {
        _review++;
      }
    });
    if (_index < length - 1) {
      _controller.nextPage(
          duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    }
  }
}

List<WordEntry> _selectCards(List<WordEntry> words, String? packId) {
  final scoped = words
      .where((word) => packId == null || word.packId == packId)
      .toList(growable: false);
  final shuffled = List<WordEntry>.of(scoped);
  shuffled.shuffle(math.Random(73));
  return shuffled;
}

class _Flashcard extends StatelessWidget {
  const _Flashcard(
      {required this.word,
      required this.showMeaning,
      required this.onFlip,
      required this.onDetail});
  final WordEntry word;
  final bool showMeaning;
  final VoidCallback onFlip;
  final VoidCallback onDetail;
  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return GestureDetector(
      onTap: onFlip,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
            gradient: showMeaning
                ? LinearGradient(colors: <Color>[tokens.hero, tokens.heroGlow])
                : tokens.accentGradient,
            borderRadius: BorderRadius.circular(30),
            boxShadow: <BoxShadow>[
              BoxShadow(
                  color: tokens.surfaceShadow,
                  blurRadius: 24,
                  offset: const Offset(0, 12))
            ]),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(children: <Widget>[
                Text(showMeaning ? 'ANLAMI' : 'KELİME',
                    style: const TextStyle(
                        color: Colors.white70,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w800)),
                const Spacer(),
                IconButton(
                    onPressed: onDetail,
                    icon: const Icon(Icons.open_in_new_rounded,
                        color: Colors.white),
                    tooltip: 'Detay')
              ]),
              const Spacer(),
              Text(showMeaning ? word.trMeaning : word.enWord,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 31,
                      height: 1.15,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Text(showMeaning ? word.enWord : word.pos,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              const Text('Çevirmek için karta dokun',
                  style: TextStyle(color: Colors.white70)),
            ]),
      ),
    );
  }
}
