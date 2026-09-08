import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/content_providers.dart';
import '../../core/local_progress.dart';
import '../../models/content_models.dart';
import '../common/page_parts.dart';
import '../words/word_detail_sheet.dart';

/// Canonical word favourites are shared with the Kelime area. This page only
/// presents that existing local state inside Testler; it owns no new storage.
class TestFavoritesPage extends ConsumerStatefulWidget {
  const TestFavoritesPage({super.key});

  @override
  ConsumerState<TestFavoritesPage> createState() => _TestFavoritesPageState();
}

class _TestFavoritesPageState extends ConsumerState<TestFavoritesPage> {
  bool _flashMode = false;
  bool _showMeaning = false;
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final words = ref.watch(wordsProvider);
    final favorites = ref.watch(localProgressProvider).favoriteWordIds;
    return words.when(
      loading: () => const PageFrame(
        title: 'Favoriler',
        subtitle: 'Kelime havuzu hazırlanıyor.',
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => DataLoadErrorPage(
        message: error.toString(),
        onRetry: () => ref.invalidate(wordsProvider),
      ),
      data: (allWords) {
        final items = allWords
            .where((word) => favorites.contains(word.id))
            .toList(growable: false);
        final safeIndex =
            items.isEmpty ? 0 : _index.clamp(0, items.length - 1).toInt();
        return PageFrame(
          title: 'Favoriler',
          subtitle: '${items.length} canonical kelime · Kelime alanıyla ortak',
          actions: <Widget>[
            OutlinedButton.icon(
              onPressed: () => context.go('/tests'),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Testlere dön'),
            ),
          ],
          child: items.isEmpty
              ? const SurfaceCard(
                  child: Text('Henüz favoriye alınmış canonical kelime yok.'),
                )
              : _flashMode
                  ? _FavoriteFlashcard(
                      word: items[safeIndex],
                      index: safeIndex,
                      total: items.length,
                      showMeaning: _showMeaning,
                      onToggle: () =>
                          setState(() => _showMeaning = !_showMeaning),
                      onPrevious: safeIndex == 0
                          ? null
                          : () => setState(() {
                                _index = safeIndex - 1;
                                _showMeaning = false;
                              }),
                      onNext: safeIndex == items.length - 1
                          ? null
                          : () => setState(() {
                                _index = safeIndex + 1;
                                _showMeaning = false;
                              }),
                      onDetails: () => _showDetails(items[safeIndex]),
                      onClose: () => setState(() => _flashMode = false),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.icon(
                            onPressed: () => setState(() {
                              _flashMode = true;
                              _showMeaning = false;
                              _index = 0;
                            }),
                            icon: const Icon(Icons.style_rounded),
                            label: const Text('Flash Kart ile çalış'),
                          ),
                        ),
                        const SizedBox(height: 14),
                        LayoutBuilder(builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 720 ? 2 : 1;
                          final width = columns == 2
                              ? (constraints.maxWidth - 12) / 2
                              : constraints.maxWidth;
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: items
                                .map((word) => SizedBox(
                                      width: width,
                                      child: _FavoriteWordCard(
                                        word: word,
                                        onTap: () => _showDetails(word),
                                      ),
                                    ))
                                .toList(growable: false),
                          );
                        }),
                      ],
                    ),
        );
      },
    );
  }

  void _showDetails(WordEntry word) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => WordDetailSheet(word: word),
    );
  }
}

class _FavoriteWordCard extends StatelessWidget {
  const _FavoriteWordCard({required this.word, required this.onTap});

  final WordEntry word;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(word.enWord, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 5),
            Text(word.trMeaning, style: Theme.of(context).textTheme.bodyLarge),
            if (word.pos.isNotEmpty) ...<Widget>[
              const SizedBox(height: 5),
              Text(word.pos, style: Theme.of(context).textTheme.bodySmall),
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
    required this.onToggle,
    required this.onPrevious,
    required this.onNext,
    required this.onDetails,
    required this.onClose,
  });

  final WordEntry word;
  final int index;
  final int total;
  final bool showMeaning;
  final VoidCallback onToggle;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onDetails;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          LinearProgressIndicator(value: (index + 1) / total),
          const SizedBox(height: 16),
          SurfaceCard(
            onTap: onToggle,
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(showMeaning ? 'Türkçe anlam' : 'İngilizce kelime',
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 14),
                  Text(showMeaning ? word.trMeaning : word.enWord,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  if (showMeaning && word.exampleEn.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 14),
                    Text(word.exampleEn,
                        style: Theme.of(context).textTheme.bodyLarge),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: onPrevious,
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Önceki'),
              ),
              OutlinedButton.icon(
                onPressed: onToggle,
                icon: Icon(showMeaning
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                label: Text(showMeaning ? 'Gizle' : 'Anlamı göster'),
              ),
              FilledButton.icon(
                onPressed: onNext,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Sonraki'),
              ),
              TextButton(
                onPressed: onDetails,
                child: const Text('Ayrıntı'),
              ),
              TextButton(
                onPressed: onClose,
                child: const Text('Listeye dön'),
              ),
            ],
          ),
        ],
      );
}
