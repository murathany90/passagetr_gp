import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme_tokens.dart';
import '../../core/content_providers.dart';
import '../../core/local_progress.dart';
import '../../models/content_models.dart';
import '../../repositories/local_progress_repository.dart';
import '../common/page_parts.dart';
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
  int _cardCount = practiceItemCountOptions.first;
  bool _showMeaning = false;
  bool _showDetails = false;
  bool _filtersRestored = false;
  String? _level;
  String? _tag;
  String? _deckKey;
  List<WordEntry> _deck = const <WordEntry>[];

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
    final progress = ref.watch(localProgressProvider);
    _restoreFilters(progress);
    return words.when(
      loading: () => const PageFrame(
        title: 'Flashcard',
        subtitle: 'Kartlar hazırlanıyor...',
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => DataLoadErrorPage(
        message: error.toString(),
        onRetry: () => ref.invalidate(wordsProvider),
      ),
      data: (allWords) {
        final levels = canonicalWordLevels(allWords);
        final tags = canonicalWordTags(allWords);
        final validLevel = levels.contains(_level) ? _level : null;
        final validTag = tags.contains(_tag) ? _tag : null;
        final eligible = wordsForFilters(
          allWords,
          level: validLevel,
          tag: validTag,
        );
        final cards = _cardsFor(
          eligible,
          key: '$validLevel|$validTag|$_cardCount|${allWords.length}',
        );
        return PageFrame(
          title: 'Flashcard',
          subtitle: cards.isEmpty
              ? 'Önce çalışma havuzunu seçin.'
              : '${_index + 1} / ${cards.length} · Bu oturum: $_known bildim, $_review tekrar',
          actions: <Widget>[
            OutlinedButton.icon(
              onPressed: () => context.go('/words'),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Kelimelere dön'),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _FlashcardFilters(
                levels: levels,
                tags: tags,
                selectedLevel: validLevel,
                selectedTag: validTag,
                cardCount: _cardCount,
                onLevelChanged: _setLevel,
                onTagChanged: _setTag,
                onCountChanged: _setCardCount,
              ),
              const SizedBox(height: 12),
              Text(
                eligible.length < _cardCount
                    ? '${eligible.length} uygun kelime bulundu; ${cards.length} kartla çalışacaksın.'
                    : '${eligible.length} uygun kelimeden ${cards.length} kart seçildi.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 18),
              if (cards.isEmpty)
                _EmptyPracticePool(onClear: _clearFilters)
              else ...<Widget>[
                LinearProgressIndicator(
                  value: (_index + 1) / cards.length,
                  minHeight: 7,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(height: 22),
                LayoutBuilder(
                  builder: (context, constraints) => SizedBox(
                    height: constraints.maxWidth < 500 ? 286 : 330,
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: cards.length,
                      onPageChanged: (value) => setState(() {
                        _index = value;
                        _showMeaning = false;
                        _showDetails = false;
                      }),
                      itemBuilder: (context, index) => _Flashcard(
                        word: cards[index],
                        showMeaning: index == _index && _showMeaning,
                        onFlip: () => setState(
                          () => _showMeaning = !_showMeaning,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const ValueKey<String>('flashcard-show-details'),
                  onPressed: () => setState(
                    () => _showDetails = !_showDetails,
                  ),
                  icon: Icon(
                    _showDetails
                        ? Icons.expand_less_rounded
                        : Icons.info_outline_rounded,
                  ),
                  label: Text(
                    _showDetails ? 'Ayrıntıyı gizle' : 'Ayrıntı göster',
                  ),
                ),
                if (_showDetails) ...<Widget>[
                  const SizedBox(height: 10),
                  _FlashcardDetails(word: cards[_index]),
                ],
                const SizedBox(height: 20),
                _FlashcardActions(
                  atFirstCard: _index == 0,
                  onPrevious: () => _controller.previousPage(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                  ),
                  onReview: () => _record(false, cards),
                  onKnown: () => _record(true, cards),
                ),
                const SizedBox(height: 14),
                Text(
                  'İlerleme yalnızca bu açık oturumda tutulur.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _restoreFilters(LocalProgressSnapshot progress) {
    if (_filtersRestored || !progress.isLoaded) {
      return;
    }
    _filtersRestored = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final restoredTag = migrateLegacyWordTag(progress.wordTag);
      setState(() {
        _level = progress.wordLevel;
        _tag = restoredTag;
        _resetDeck();
      });
      if (restoredTag != progress.wordTag) {
        ref.read(localProgressProvider.notifier).setWordFilters(
              tag: restoredTag,
              level: progress.wordLevel,
            );
      }
    });
  }

  List<WordEntry> _cardsFor(List<WordEntry> eligible, {required String key}) {
    if (_deckKey == key) {
      return _deck;
    }
    final shuffled = List<WordEntry>.of(eligible)..shuffle(math.Random());
    _deck = shuffled.take(_cardCount).toList(growable: false);
    _deckKey = key;
    return _deck;
  }

  void _record(bool known, List<WordEntry> cards) {
    setState(() {
      if (known) {
        _known++;
      } else {
        _review++;
      }
      _showDetails = false;
    });
    if (known) {
      ref.read(localProgressProvider.notifier).markWordKnown(cards[_index].id);
    }
    if (_index < cards.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  void _setLevel(String? value) => _applyFilters(level: value, tag: _tag);

  void _setTag(String? value) => _applyFilters(level: _level, tag: value);

  void _setCardCount(int? value) {
    if (value == null || value == _cardCount) {
      return;
    }
    setState(() {
      _cardCount = value;
      _resetSession();
    });
  }

  void _clearFilters() => _applyFilters(level: null, tag: null);

  void _applyFilters({required String? level, required String? tag}) {
    setState(() {
      _level = level;
      _tag = tag;
      _resetSession();
    });
    ref.read(localProgressProvider.notifier).setWordFilters(
          tag: tag,
          level: level,
        );
  }

  void _resetSession() {
    _index = 0;
    _known = 0;
    _review = 0;
    _showMeaning = false;
    _showDetails = false;
    _resetDeck();
    if (_controller.hasClients) {
      _controller.jumpToPage(0);
    }
  }

  void _resetDeck() {
    _deckKey = null;
    _deck = const <WordEntry>[];
  }
}

class _FlashcardFilters extends StatelessWidget {
  const _FlashcardFilters({
    required this.levels,
    required this.tags,
    required this.selectedLevel,
    required this.selectedTag,
    required this.cardCount,
    required this.onLevelChanged,
    required this.onTagChanged,
    required this.onCountChanged,
  });

  final List<String> levels;
  final List<String> tags;
  final String? selectedLevel;
  final String? selectedTag;
  final int cardCount;
  final ValueChanged<String?> onLevelChanged;
  final ValueChanged<String?> onTagChanged;
  final ValueChanged<int?> onCountChanged;

  @override
  Widget build(BuildContext context) => Column(
        children: <Widget>[
          DropdownButtonFormField<String?>(
            key: ValueKey<String?>('flashcard-level-$selectedLevel'),
            initialValue: selectedLevel,
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
            onChanged: onLevelChanged,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            key: ValueKey<String?>('flashcard-tag-$selectedTag'),
            initialValue: selectedTag,
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
            onChanged: onTagChanged,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            key: ValueKey<int>(cardCount),
            initialValue: cardCount,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Kart sayısı'),
            items: practiceItemCountOptions
                .map(
                  (count) => DropdownMenuItem(
                    value: count,
                    child: Text('$count kart'),
                  ),
                )
                .toList(growable: false),
            onChanged: onCountChanged,
          ),
        ],
      );
}

class _EmptyPracticePool extends StatelessWidget {
  const _EmptyPracticePool({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.filter_alt_off_rounded, size: 30),
            const SizedBox(height: 10),
            Text(
              'Bu filtrelerle eşleşen kelime yok.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text('Filtreleri değiştir veya tüm kelimelere dön.'),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              key: const ValueKey<String>('flashcard-clear-filters'),
              onPressed: onClear,
              icon: const Icon(Icons.filter_alt_off_rounded),
              label: const Text('Filtreleri temizle'),
            ),
          ],
        ),
      );
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

class _Flashcard extends StatelessWidget {
  const _Flashcard({
    required this.word,
    required this.showMeaning,
    required this.onFlip,
  });

  final WordEntry word;
  final bool showMeaning;
  final VoidCallback onFlip;

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
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              showMeaning ? 'ANLAMI' : 'KELİME',
              style: const TextStyle(
                color: Colors.white70,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            Text(
              showMeaning ? word.trMeaning : word.enWord,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 31,
                height: 1.15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              showMeaning ? word.enWord : word.pos,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            const Text(
              'Çevirmek için karta dokun',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlashcardDetails extends StatelessWidget {
  const _FlashcardDetails({required this.word});

  final WordEntry word;

  @override
  Widget build(BuildContext context) {
    final details = <_DetailValue>[
      _DetailValue('Anlam', word.trMeaning),
      if (_notBlank(word.synonymsRaw))
        _DetailValue('Eş anlamlılar', word.synonymsRaw!),
      if (_notBlank(word.antonymsRaw))
        _DetailValue('Zıt anlamlılar', word.antonymsRaw!),
      if (_notBlank(word.exampleEn)) _DetailValue('Örnek', word.exampleEn),
      if (_notBlank(word.exampleTr)) _DetailValue('Çeviri', word.exampleTr!),
      if (_notBlank(word.level)) _DetailValue('Seviye', word.level!),
      if (word.tags.isNotEmpty)
        _DetailValue('Etiketler', word.tags.join(' · ')),
    ];
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: details
            .map(
              (detail) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: RichText(
                  text: TextSpan(
                    style: Theme.of(context).textTheme.bodyMedium,
                    children: <InlineSpan>[
                      TextSpan(
                        text: '${detail.label}: ',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      TextSpan(text: detail.value),
                    ],
                  ),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _DetailValue {
  const _DetailValue(this.label, this.value);

  final String label;
  final String value;
}

bool _notBlank(String? value) => value?.trim().isNotEmpty ?? false;
