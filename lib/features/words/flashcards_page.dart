import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme_tokens.dart';
import '../../core/content_providers.dart';
import '../../core/local_progress.dart';
import '../../models/content_models.dart';
import '../common/page_parts.dart';
import 'word_detail_sheet.dart';
import 'word_filtering.dart';

class FlashcardsPage extends ConsumerStatefulWidget {
  const FlashcardsPage({super.key});
  @override
  ConsumerState<FlashcardsPage> createState() => _FlashcardsPageState();
}

class _FlashcardsPageState extends ConsumerState<FlashcardsPage> {
  late final PageController _controller;
  int _index = 0;
  int _known = 0;
  int _review = 0;
  bool _showMeaning = false;
  String? _level;
  String? _tag;

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
        final levels = canonicalWordLevels(allWords);
        final tags = canonicalWordTags(allWords);
        final validLevel = levels.contains(_level) ? _level : null;
        final validTag = tags.contains(_tag) ? _tag : null;
        final words = _selectCards(
          allWords,
          level: validLevel,
          tag: validTag,
        );
        if (words.isEmpty) {
          return const DataLoadErrorPage(
              message: 'DATA_LOAD_ERROR: Bu filtreler için kelime bulunamadı.');
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
            DropdownButtonFormField<String?>(
              key: ValueKey<String?>('flashcard-level-$validLevel'),
              initialValue: validLevel,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Seviye'),
              items: <DropdownMenuItem<String?>>[
                const DropdownMenuItem(
                  value: null,
                  child: Text('Tüm seviyeler'),
                ),
                ...levels.map(
                  (level) => DropdownMenuItem(
                    value: level,
                    child: Text(level),
                  ),
                ),
              ],
              onChanged: _setLevel,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: ValueKey<String?>('flashcard-tag-$validTag'),
              initialValue: validTag,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Etiket'),
              items: <DropdownMenuItem<String?>>[
                const DropdownMenuItem(
                  value: null,
                  child: Text('Tüm etiketler'),
                ),
                ...tags.map(
                  (tag) => DropdownMenuItem(value: tag, child: Text(tag)),
                ),
              ],
              onChanged: _setTag,
            ),
            const SizedBox(height: 18),
            LinearProgressIndicator(
                value: (_index + 1) / words.length,
                minHeight: 7,
                borderRadius: BorderRadius.circular(8)),
            const SizedBox(height: 26),
            LayoutBuilder(
              builder: (context, constraints) => SizedBox(
                height: constraints.maxWidth < 500 ? 286 : 330,
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
                      onFlip: () =>
                          setState(() => _showMeaning = !_showMeaning),
                      onDetail: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => WordDetailSheet(word: words[index]))),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _FlashcardActions(
              atFirstCard: _index == 0,
              onPrevious: () => _controller.previousPage(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut),
              onReview: () => _record(false, words),
              onKnown: () => _record(true, words),
            ),
            const SizedBox(height: 14),
            Text('İlerleme yalnızca bu açık oturumda tutulur.',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
        );
      },
    );
  }

  void _record(bool known, List<WordEntry> words) {
    setState(() {
      if (known) {
        _known++;
      } else {
        _review++;
      }
    });
    if (known) {
      ref.read(localProgressProvider.notifier).markWordKnown(words[_index].id);
    }
    if (_index < words.length - 1) {
      _controller.nextPage(
          duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    }
  }

  void _setLevel(String? value) => _applyFilters(level: value, tag: _tag);

  void _setTag(String? value) => _applyFilters(level: _level, tag: value);

  void _applyFilters({required String? level, required String? tag}) {
    setState(() {
      _level = level;
      _tag = tag;
      _index = 0;
      _showMeaning = false;
    });
    if (_controller.hasClients) {
      _controller.jumpToPage(0);
    }
  }
}

class _FlashcardActions extends StatelessWidget {
  const _FlashcardActions({
    required this.atFirstCard,
    required this.onPrevious,
    required this.onReview,
    required this.onKnown,
  });

  final bool atFirstCard;
  final VoidCallback onPrevious;
  final VoidCallback onReview;
  final VoidCallback onKnown;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final previous = OutlinedButton.icon(
            onPressed: atFirstCard ? null : onPrevious,
            icon: const Icon(Icons.chevron_left_rounded),
            label: const Text('Önceki'),
          );
          final review = FilledButton.icon(
            onPressed: onReview,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Tekrar'),
          );
          final known = FilledButton.icon(
            onPressed: onKnown,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Bildim'),
          );
          if (constraints.maxWidth >= 500) {
            return Row(children: <Widget>[
              Expanded(child: previous),
              const SizedBox(width: 12),
              Expanded(child: review),
              const SizedBox(width: 12),
              Expanded(child: known),
            ]);
          }
          return Column(children: <Widget>[
            Row(children: <Widget>[
              Expanded(child: review),
              const SizedBox(width: 12),
              Expanded(child: known),
            ]),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: previous),
          ]);
        },
      );
}

List<WordEntry> _selectCards(
  List<WordEntry> words, {
  String? level,
  String? tag,
}) {
  final scoped = words
      .where((word) => matchesWordFilters(word, level: level, tag: tag))
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
