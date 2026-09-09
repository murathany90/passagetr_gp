import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_breakpoints.dart';
import '../../core/app_theme_tokens.dart';
import '../../core/content_providers.dart';
import '../../core/local_progress.dart';
import '../../core/presentation_order.dart';
import '../../models/content_models.dart';
import '../common/page_parts.dart';
import '../words/word_filtering.dart';
import 'reading_artwork.dart';
import 'reading_models.dart';

class ReadingsPage extends ConsumerStatefulWidget {
  const ReadingsPage({super.key});
  @override
  ConsumerState<ReadingsPage> createState() => _ReadingsPageState();
}

class _ReadingsPageState extends ConsumerState<ReadingsPage> {
  static const _pageSize = 20;
  String _query = '';
  String? _level;
  String? _category;
  int _page = 0;
  bool _filtersRestored = false;
  late final TextEditingController _searchController;
  Timer? _searchDebounce;
  late int _shuffleSeed;
  var _order = PresentationOrder.alphabetical;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _shuffleSeed = createPresentationSeed();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _query = '';
      _page = 0;
    });
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      final nextQuery = value.trim();
      if (nextQuery == _query) return;
      setState(() {
        _query = nextQuery;
        _page = 0;
      });
    });
  }

  void _reshuffle() {
    setState(() {
      _shuffleSeed = createPresentationSeed(previousSeed: _shuffleSeed);
      _order = PresentationOrder.mixed;
      _page = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final readings = ref.watch(readingsProvider);
    final progress = ref.watch(localProgressProvider.select((state) => (
          isLoaded: state.isLoaded,
          level: state.readingLevel,
          category: state.readingCategory,
          completedReadingIds: state.completedReadingIds,
        )));
    // Legacy (001–678) progress migration runs once in the background.
    ref.watch(readingProgressMigrationProvider);
    if (!_filtersRestored && progress.isLoaded) {
      _filtersRestored = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _level = progress.level;
            _category = progress.category;
          });
        }
      });
    }
    return readings.when(
      loading: () => const PageFrame(
          title: 'Okuma',
          subtitle: 'Okuma kütüphanesi yükleniyor...',
          child: Center(
              child: Padding(
                  padding: EdgeInsets.all(48),
                  child: CircularProgressIndicator()))),
      error: (error, _) => DataLoadErrorPage(
          message: error.toString(),
          onRetry: () => ref.invalidate(readingsProvider)),
      data: (items) {
        final allLevels = _canonicalLevelList(items.map((item) => item.level));
        final allCategories = items
            .map((item) => item.category)
            .whereType<String>()
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        var validLevel = allLevels.contains(_level) ? _level : null;
        var validCategory =
            allCategories.contains(_category) ? _category : null;
        final levels = _canonicalLevelList(items
            .where(
              (item) => validCategory == null || item.category == validCategory,
            )
            .map((item) => item.level));
        final categories = items
            .where((item) => validLevel == null || item.level == validLevel)
            .map((item) => item.category)
            .whereType<String>()
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        if (validLevel != null && !levels.contains(validLevel)) {
          validLevel = null;
        }
        if (validCategory != null && !categories.contains(validCategory)) {
          validCategory = null;
        }
        if (_level != validLevel || _category != validCategory) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _level = validLevel;
              _category = validCategory;
              _page = 0;
            });
            ref
                .read(localProgressProvider.notifier)
                .setReadingFilters(level: validLevel, category: validCategory);
          });
        }
        final queryLower = _query.toLowerCase();
        final filtered = items.where((item) {
          final text =
              '${item.sourceNumber ?? ''} ${item.title} ${item.displayTitle ?? ''} ${item.turkishTitle ?? ''} ${item.level ?? ''} ${item.category ?? ''} ${item.tags.join(' ')}'
                  .toLowerCase();
          return (validLevel == null || item.level == validLevel) &&
              (validCategory == null || item.category == validCategory) &&
              text.contains(queryLower);
        }).toList(growable: false);
        final ordered = orderForPresentation<ReadingPassage>(
          filtered,
          order: _order,
          hasSearchQuery: _query.isNotEmpty,
          sessionSeed: _shuffleSeed,
          alphabeticalComparator: (left, right) {
            final bySourceNumber =
                (int.tryParse(left.sourceNumber ?? '') ?? (1 << 30)).compareTo(
              int.tryParse(right.sourceNumber ?? '') ?? (1 << 30),
            );
            return bySourceNumber != 0
                ? bySourceNumber
                : left.id.compareTo(right.id);
          },
        );
        final lastPage =
            ordered.isEmpty ? 0 : (ordered.length - 1) ~/ _pageSize;
        final page = _page.clamp(0, lastPage);
        final visible = ordered
            .skip(page * _pageSize)
            .take(_pageSize)
            .toList(growable: false);
        return PageFrame(
          title: 'Okuma',
          subtitle:
              '${items.length} metin; her okuma kendi kaynak cümleleriyle açılır.',
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        hintText: 'Başlık, kategori veya seviye ara...',
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Aramayı temizle',
                                onPressed: _clearSearch,
                                icon: const Icon(Icons.clear_rounded),
                              )),
                    onChanged: _onSearchChanged),
                const SizedBox(height: 14),
                DropdownButtonFormField<String?>(
                  key: ValueKey<String?>('level-$validLevel'),
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
                  onChanged: (value) {
                    final availableCategories = items
                        .where(
                          (item) => value == null || item.level == value,
                        )
                        .map((item) => item.category)
                        .whereType<String>()
                        .where((category) => category.isNotEmpty)
                        .toSet();
                    final nextCategory =
                        availableCategories.contains(validCategory)
                            ? validCategory
                            : null;
                    setState(() {
                      _level = value;
                      _category = nextCategory;
                      _page = 0;
                    });
                    ref.read(localProgressProvider.notifier).setReadingFilters(
                          level: value,
                          category: nextCategory,
                        );
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String?>(
                  key: ValueKey<String?>('category-$validCategory'),
                  initialValue: validCategory,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Kategori'),
                  items: <DropdownMenuItem<String?>>[
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Tüm kategoriler'),
                    ),
                    ...categories.map(
                      (category) => DropdownMenuItem(
                        value: category,
                        child: Text(category),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    final availableLevels = items
                        .where(
                          (item) => value == null || item.category == value,
                        )
                        .map((item) => item.level)
                        .whereType<String>()
                        .where((level) => level.isNotEmpty)
                        .toSet();
                    final nextLevel = availableLevels.contains(validLevel)
                        ? validLevel
                        : null;
                    setState(() {
                      _category = value;
                      _level = nextLevel;
                      _page = 0;
                    });
                    ref
                        .read(localProgressProvider.notifier)
                        .setReadingFilters(level: nextLevel, category: value);
                  },
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    SegmentedButton<PresentationOrder>(
                      showSelectedIcon: false,
                      segments: const <ButtonSegment<PresentationOrder>>[
                        ButtonSegment(
                          value: PresentationOrder.alphabetical,
                          label: Text('Normal'),
                        ),
                        ButtonSegment(
                          value: PresentationOrder.mixed,
                          label: Text('Karışık'),
                        ),
                      ],
                      selected: <PresentationOrder>{_order},
                      onSelectionChanged: (selection) => setState(() {
                        _order = selection.single;
                        _page = 0;
                      }),
                    ),
                    OutlinedButton.icon(
                      onPressed: _reshuffle,
                      icon: const Icon(Icons.shuffle_rounded, size: 18),
                      label: const Text('Karıştır'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(children: <Widget>[
                  Expanded(
                    child: Text('${filtered.length} sonuç',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  if (validLevel != null || validCategory != null)
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _level = null;
                          _category = null;
                          _page = 0;
                        });
                        ref
                            .read(localProgressProvider.notifier)
                            .setReadingFilters();
                      },
                      icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                      label: const Text('Sıfırla'),
                    ),
                ]),
                const SizedBox(height: 2),
                Text('İlerleme bu tarayıcıda saklanır.',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                _ReadingPager(
                    page: page,
                    lastPage: lastPage,
                    onPrevious: page == 0
                        ? null
                        : () => setState(() => _page = page - 1),
                    onNext: page == lastPage
                        ? null
                        : () => setState(() => _page = page + 1)),
                const SizedBox(height: 8),
                _ReadingGrid(
                  readings: visible,
                  completedReadingIds: progress.completedReadingIds,
                ),
              ]),
        );
      },
    );
  }
}

/// Canonical CEFR order (A1 → C2) for every reading level list.
List<String> _canonicalLevelList(Iterable<String?> levels) {
  final ordered = levels
      .whereType<String>()
      .where((level) => level.isNotEmpty)
      .toSet()
      .toList();
  ordered.sort((left, right) {
    final leftRank = canonicalLevelOrder.indexOf(left);
    final rightRank = canonicalLevelOrder.indexOf(right);
    final rank = (leftRank < 0 ? canonicalLevelOrder.length : leftRank)
        .compareTo(rightRank < 0 ? canonicalLevelOrder.length : rightRank);
    return rank != 0 ? rank : left.compareTo(right);
  });
  return ordered;
}

class _ReadingPager extends StatelessWidget {
  const _ReadingPager({
    required this.page,
    required this.lastPage,
    required this.onPrevious,
    required this.onNext,
  });

  final int page;
  final int lastPage;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) => Row(children: <Widget>[
        Expanded(
            child: Text('Sayfa ${page + 1}/${lastPage + 1}',
                style: Theme.of(context).textTheme.bodyMedium)),
        IconButton(
            tooltip: 'Önceki sayfa',
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded)),
        IconButton(
            tooltip: 'Sonraki sayfa',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded)),
      ]);
}

class _ReadingGrid extends StatelessWidget {
  const _ReadingGrid({
    required this.readings,
    required this.completedReadingIds,
  });
  final List<ReadingPassage> readings;
  final Set<String> completedReadingIds;
  @override
  Widget build(BuildContext context) {
    if (readings.isEmpty) {
      return const SurfaceCard(child: Text('Aramana uygun okuma bulunamadı.'));
    }
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= AppBreakpoints.desktopWide
          ? 3
          : constraints.maxWidth >= AppBreakpoints.mobileWide
              ? 2
              : 1;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: readings.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            mainAxisExtent: columns == 1 ? 268 : 332),
        itemBuilder: (context, index) => _ReadingCard(
          passage: readings[index],
          compact: columns == 1,
          completed: completedReadingIds.contains(readings[index].id),
        ),
      );
    });
  }
}

class _ReadingCard extends StatelessWidget {
  const _ReadingCard({
    required this.passage,
    required this.compact,
    required this.completed,
  });
  final ReadingPassage passage;
  final bool compact;
  final bool completed;
  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return SurfaceCard(
      padding: EdgeInsets.zero,
      elevated: false,
      onTap: () => context.go('/readings/${passage.id}'),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ReadingArtwork(
                passage: passage,
                height: compact ? 124 : 145,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24))),
            Expanded(
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(17, 14, 17, 16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Wrap(spacing: 7, runSpacing: 5, children: <Widget>[
                            if (passage.level != null)
                              _ReadingPill(
                                  label: passage.level!, color: tokens.hero),
                            if (passage.category != null)
                              _ReadingPill(
                                  label: passage.category!,
                                  color: tokens.purple),
                            if (passage.estimatedReadingMinutes > 0)
                              _ReadingPill(
                                  label:
                                      '~${passage.estimatedReadingMinutes} dk',
                                  color: tokens.accentBlue),
                            if (completed)
                              _ReadingPill(
                                  label: 'Tamamlandı', color: tokens.success),
                          ]),
                          const Spacer(),
                          Text(readingPassageDisplayTitle(passage),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 7),
                          Text(_metadataFor(passage),
                              style: Theme.of(context).textTheme.bodySmall),
                        ]))),
          ]),
    );
  }
}

String _metadataFor(ReadingPassage passage) {
  final values = <String>['${passage.sentenceCount} cümle'];
  if (passage.wordCount > 0) values.add('${passage.wordCount} kelime');
  if (passage.estimatedReadingMinutes > 0) {
    values.add('~${passage.estimatedReadingMinutes} dk');
  }
  return values.join(' · ');
}

class _ReadingPill extends StatelessWidget {
  const _ReadingPill({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(12)),
      child: Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              Theme.of(context).textTheme.bodySmall?.copyWith(color: color)));
}
