import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_breakpoints.dart';
import '../../core/app_theme_tokens.dart';
import '../../core/content_providers.dart';
import '../../core/local_progress.dart';
import '../../models/content_models.dart';
import '../common/page_parts.dart';
import 'reading_artwork.dart';

class ReadingsPage extends ConsumerStatefulWidget {
  const ReadingsPage({super.key});
  @override
  ConsumerState<ReadingsPage> createState() => _ReadingsPageState();
}

class _ReadingsPageState extends ConsumerState<ReadingsPage> {
  static const _pageSize = 48;
  String _query = '';
  String? _packId;
  String? _level;
  String? _category;
  int _page = 0;
  bool _filtersRestored = false;

  @override
  Widget build(BuildContext context) {
    final readings = ref.watch(readingsProvider);
    final packs = ref.watch(contentPacksProvider);
    final progress = ref.watch(localProgressProvider);
    if (!_filtersRestored && progress.isLoaded) {
      _filtersRestored = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _level = progress.readingLevel;
            _category = progress.readingCategory;
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
        final packItems = packs.valueOrNull ?? const <ContentPack>[];
        final availablePackIds = items.map((item) => item.packId).toSet();
        final validPackId = availablePackIds.contains(_packId) ? _packId : null;
        final levels = items
            .map((item) => item.level)
            .whereType<String>()
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        final categories = items
            .map((item) => item.category)
            .whereType<String>()
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        final validLevel = levels.contains(_level) ? _level : null;
        final validCategory = categories.contains(_category) ? _category : null;
        final filtered = items.where((item) {
          final text =
              '${item.title} ${item.level ?? ''} ${item.category ?? ''} ${item.tags.join(' ')}'
                  .toLowerCase();
          return (validPackId == null || item.packId == validPackId) &&
              (validLevel == null || item.level == validLevel) &&
              (validCategory == null || item.category == validCategory) &&
              text.contains(_query.toLowerCase());
        }).toList(growable: false);
        final lastPage =
            filtered.isEmpty ? 0 : (filtered.length - 1) ~/ _pageSize;
        final page = _page.clamp(0, lastPage);
        final visible = filtered
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
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded),
                        hintText: 'Başlık, kategori veya seviye ara...'),
                    onChanged: (value) => setState(() {
                          _query = value.trim();
                          _page = 0;
                        })),
                const SizedBox(height: 14),
                DropdownButtonFormField<String?>(
                  key: ValueKey<String?>(validPackId),
                  initialValue: validPackId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Paket'),
                  items: <DropdownMenuItem<String?>>[
                    const DropdownMenuItem(
                        value: null, child: Text('Tüm okumalar')),
                    ...packItems
                        .where((pack) => availablePackIds.contains(pack.id))
                        .map((pack) => DropdownMenuItem(
                            value: pack.id, child: Text(pack.name))),
                  ],
                  onChanged: (value) => setState(() {
                    _packId = value;
                    _page = 0;
                  }),
                ),
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
                    setState(() {
                      _level = value;
                      _page = 0;
                    });
                    ref
                        .read(localProgressProvider.notifier)
                        .setReadingFilters(level: value, category: _category);
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
                    setState(() {
                      _category = value;
                      _page = 0;
                    });
                    ref
                        .read(localProgressProvider.notifier)
                        .setReadingFilters(level: _level, category: value);
                  },
                ),
                const SizedBox(height: 12),
                Row(children: <Widget>[
                  Expanded(
                    child: Text('${filtered.length} sonuç',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  if (validPackId != null ||
                      validLevel != null ||
                      validCategory != null)
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _packId = null;
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
                            if (passage.durationMinutes != null)
                              _ReadingPill(
                                  label: '${passage.durationMinutes} dk',
                                  color: tokens.accentBlue),
                            if (completed)
                              _ReadingPill(
                                  label: 'Tamamlandı', color: tokens.success),
                          ]),
                          const Spacer(),
                          Text(passage.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 7),
                          Text('${passage.sentenceCount} cümle',
                              style: Theme.of(context).textTheme.bodySmall),
                        ]))),
          ]),
    );
  }
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
