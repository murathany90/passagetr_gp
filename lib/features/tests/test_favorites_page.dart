import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/content_providers.dart';
import '../../core/local_progress.dart';
import '../../models/test_models.dart';
import '../common/page_parts.dart';

/// A private Test Bank collection. It intentionally never reads the main
/// Words favourite set, so the two learning areas stay independent.
class TestFavoritesPage extends ConsumerStatefulWidget {
  const TestFavoritesPage({super.key});

  @override
  ConsumerState<TestFavoritesPage> createState() => _TestFavoritesPageState();
}

class _TestFavoritesPageState extends ConsumerState<TestFavoritesPage> {
  static const _listPageSize = 20;
  List<TestBankWord> _deck = const <TestBankWord>[];
  int _index = 0;
  int _listPage = 0;
  bool _showMeaning = false;
  bool _flashMode = false;

  @override
  Widget build(BuildContext context) {
    final favorites = ref.watch(testFavoriteWordsProvider);
    return favorites.when(
      loading: () => const PageFrame(
        title: 'Test favorileri',
        subtitle: 'Test Bank kelimeleri hazırlanıyor.',
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => DataLoadErrorPage(
        message: error.toString(),
        onRetry: () => ref.invalidate(testFavoriteWordsProvider),
      ),
      data: (items) {
        _synchronizeDeck(items);
        if (items.isEmpty) {
          return PageFrame(
            title: 'Test favorileri',
            subtitle: 'Yalnız Test Bank kelimeleri gösterilir.',
            actions: <Widget>[_backButton(context)],
            child: const SurfaceCard(
              child: Text('Henüz Testler içinde favoriye alınmış kelime yok.'),
            ),
          );
        }
        final safeIndex = _index.clamp(0, _deck.length - 1).toInt();
        return PageFrame(
          title: 'Test favorileri',
          subtitle:
              '${items.length} Test Bank kelimesi · Kelime favorilerinden ayrıdır.',
          actions: <Widget>[_backButton(context)],
          child: _flashMode
              ? _FavoriteFlashcard(
                  word: _deck[safeIndex],
                  index: safeIndex,
                  total: _deck.length,
                  showMeaning: _showMeaning,
                  known: ref
                      .watch(localProgressProvider)
                      .testFlashcardKnownIds
                      .contains(_deck[safeIndex].id),
                  onFlip: () => setState(() => _showMeaning = !_showMeaning),
                  onPrevious: safeIndex == 0 ? null : () => _move(-1),
                  onNext: safeIndex == _deck.length - 1 ? null : () => _move(1),
                  onRetry: () => _move(1),
                  onKnow: () {
                    ref
                        .read(localProgressProvider.notifier)
                        .markTestFlashcardKnown(_deck[safeIndex].id);
                    _move(1);
                  },
                  onRemove: () => ref
                      .read(localProgressProvider.notifier)
                      .toggleTestFavoriteWord(_deck[safeIndex].id),
                  onShuffle: _shuffle,
                  onClose: () => setState(() => _flashMode = false),
                )
              : _FavoriteList(
                  items: _deck,
                  page: _listPage,
                  pageSize: _listPageSize,
                  onStart: () => setState(() {
                    _flashMode = true;
                    _showMeaning = false;
                    _index = 0;
                  }),
                  onShuffle: _shuffle,
                  onPageChanged: (page) => setState(() => _listPage = page),
                  onRemove: (word) => ref
                      .read(localProgressProvider.notifier)
                      .toggleTestFavoriteWord(word.id),
                ),
        );
      },
    );
  }

  Widget _backButton(BuildContext context) => OutlinedButton.icon(
        onPressed: () => context.go('/tests'),
        icon: const Icon(Icons.arrow_back_rounded),
        label: const Text('Testlere dön'),
      );

  void _synchronizeDeck(List<TestBankWord> items) {
    final ids = items.map((word) => word.id).toSet();
    if (_deck.length == items.length &&
        _deck.every((word) => ids.contains(word.id))) {
      return;
    }
    _deck = List<TestBankWord>.of(items)..shuffle(math.Random());
    _index = 0;
    _listPage = 0;
    _showMeaning = false;
  }

  void _shuffle() => setState(() {
        _deck.shuffle(math.Random());
        _index = 0;
        _listPage = 0;
        _showMeaning = false;
      });

  void _move(int offset) => setState(() {
        _index = (_index + offset).clamp(0, _deck.length - 1).toInt();
        _showMeaning = false;
      });
}

class _FavoriteList extends StatelessWidget {
  const _FavoriteList({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.onStart,
    required this.onShuffle,
    required this.onPageChanged,
    required this.onRemove,
  });

  final List<TestBankWord> items;
  final int page;
  final int pageSize;
  final VoidCallback onStart;
  final VoidCallback onShuffle;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<TestBankWord> onRemove;

  @override
  Widget build(BuildContext context) {
    final lastPage = (items.length - 1) ~/ pageSize;
    final safePage = page.clamp(0, lastPage).toInt();
    final visible =
        items.skip(safePage * pageSize).take(pageSize).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
          FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.style_rounded),
            label: const Text('Flash kart ile çalış'),
          ),
          OutlinedButton.icon(
            onPressed: onShuffle,
            icon: const Icon(Icons.shuffle_rounded),
            label: const Text('Karıştır'),
          ),
        ]),
        const SizedBox(height: 14),
        if (lastPage > 0) ...<Widget>[
          Row(children: <Widget>[
            Expanded(
                child: Text('Sayfa ${safePage + 1}/${lastPage + 1}',
                    style: Theme.of(context).textTheme.bodyMedium)),
            IconButton(
                tooltip: 'Önceki sayfa',
                onPressed:
                    safePage == 0 ? null : () => onPageChanged(safePage - 1),
                icon: const Icon(Icons.chevron_left_rounded)),
            IconButton(
                tooltip: 'Sonraki sayfa',
                onPressed: safePage == lastPage
                    ? null
                    : () => onPageChanged(safePage + 1),
                icon: const Icon(Icons.chevron_right_rounded)),
          ]),
          const SizedBox(height: 10),
        ],
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth >= 720 ? 2 : 1;
          final width = columns == 2
              ? (constraints.maxWidth - 12) / 2
              : constraints.maxWidth;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: visible
                .map((word) => SizedBox(
                      width: width,
                      child: _FavoriteWordCard(
                        word: word,
                        onRemove: () => onRemove(word),
                      ),
                    ))
                .toList(growable: false),
          );
        }),
      ],
    );
  }
}

class _FavoriteWordCard extends StatelessWidget {
  const _FavoriteWordCard({required this.word, required this.onRemove});

  final TestBankWord word;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        elevated: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(children: <Widget>[
              Expanded(
                child: Text(word.headword,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              IconButton(
                tooltip: 'Favoriden çıkar',
                onPressed: onRemove,
                icon: const Icon(Icons.favorite_rounded),
              ),
            ]),
            Text(word.meaningTr, style: Theme.of(context).textTheme.bodyLarge),
            if (word.pos.isNotEmpty) ...<Widget>[
              const SizedBox(height: 5),
              Text(word.pos, style: Theme.of(context).textTheme.bodySmall),
            ],
            if (word.exampleEn.isNotEmpty) ...<Widget>[
              const SizedBox(height: 9),
              Text(word.exampleEn,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      );
}

class _FavoriteFlashcard extends StatelessWidget {
  const _FavoriteFlashcard({
    required this.word,
    required this.index,
    required this.total,
    required this.showMeaning,
    required this.known,
    required this.onFlip,
    required this.onPrevious,
    required this.onNext,
    required this.onRetry,
    required this.onKnow,
    required this.onRemove,
    required this.onShuffle,
    required this.onClose,
  });

  final TestBankWord word;
  final int index;
  final int total;
  final bool showMeaning;
  final bool known;
  final VoidCallback onFlip;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onRetry;
  final VoidCallback onKnow;
  final VoidCallback onRemove;
  final VoidCallback onShuffle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          LinearProgressIndicator(value: (index + 1) / total),
          const SizedBox(height: 16),
          SurfaceCard(
            onTap: onFlip,
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(children: <Widget>[
                    Expanded(
                      child: Text(
                          showMeaning ? 'Türkçe anlam' : 'İngilizce kelime',
                          style: Theme.of(context).textTheme.labelLarge),
                    ),
                    IconButton(
                      tooltip: 'Favoriden çıkar',
                      onPressed: onRemove,
                      icon: const Icon(Icons.favorite_rounded),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  Text(showMeaning ? word.meaningTr : word.headword,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  if (!showMeaning && word.pos.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(word.pos,
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                  if (showMeaning && word.exampleEn.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 14),
                    Text(word.exampleEn,
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
            OutlinedButton.icon(
              onPressed: onPrevious,
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Önceki'),
            ),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.replay_rounded),
              label: const Text('Tekrar'),
            ),
            FilledButton.icon(
              onPressed: onKnow,
              icon: Icon(
                  known ? Icons.check_circle_rounded : Icons.check_rounded),
              label: const Text('Bildim'),
            ),
            TextButton.icon(
              onPressed: onShuffle,
              icon: const Icon(Icons.shuffle_rounded),
              label: const Text('Karıştır'),
            ),
            TextButton(onPressed: onClose, child: const Text('Listeye dön')),
          ]),
        ],
      );
}
