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
import '../tts/student_tts_icon_button.dart';
import 'word_detail_sheet.dart';
import 'word_filtering.dart';

class WordsPage extends ConsumerStatefulWidget {
  const WordsPage({super.key, this.initialQuery});
  final String? initialQuery;
  @override
  ConsumerState<WordsPage> createState() => _WordsPageState();
}

class _WordsPageState extends ConsumerState<WordsPage> {
  static const _pageSize = 72;
  String _query = '';
  String? _tag;
  String? _level;
  bool _favoritesOnly = false;
  bool _showTranslations = true;
  int _page = 0;
  bool _filtersRestored = false;
  late final TextEditingController _searchController;
  late int _shuffleSeed;
  var _order = PresentationOrder.mixed;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery ?? '';
    _searchController = TextEditingController(text: _query);
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
    final trimmed = value.trim();
    if (trimmed == _query) return;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      setState(() {
        _query = trimmed;
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
    final words = ref.watch(wordsProvider);
    final progress = ref.watch(localProgressProvider);
    if (!_filtersRestored && progress.isLoaded) {
      _filtersRestored = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final restoredTag = migrateLegacyWordTag(progress.wordTag);
          setState(() {
            _tag = restoredTag;
            _level = progress.wordLevel;
          });
          if (restoredTag != progress.wordTag) {
            ref.read(localProgressProvider.notifier).setWordFilters(
                  tag: restoredTag,
                  level: progress.wordLevel,
                );
          }
        }
      });
    }
    return words.when(
      loading: () => const PageFrame(
          title: 'Kelimeler',
          subtitle: 'İçerik yükleniyor...',
          child: _WordsLoading()),
      error: (error, _) => DataLoadErrorPage(
          message: error.toString(),
          onRetry: () => ref.invalidate(wordsProvider)),
      data: (items) {
        final filterBase = items
            .where(
              (word) =>
                  !_favoritesOnly || progress.favoriteWordIds.contains(word.id),
            )
            .toList(growable: false);
        final allTags = canonicalWordTags(filterBase);
        final allLevels = canonicalWordLevels(filterBase);
        var validTag = allTags.contains(_tag) ? _tag : null;
        var validLevel = allLevels.contains(_level) ? _level : null;
        final tags = canonicalWordTags(
          filterBase.where(
            (word) => validLevel == null || word.level == validLevel,
          ),
        );
        final levels = canonicalWordLevels(
          filterBase.where(
            (word) => validTag == null || word.tags.contains(validTag),
          ),
        );
        if (validTag != null && !tags.contains(validTag)) validTag = null;
        if (validLevel != null && !levels.contains(validLevel)) {
          validLevel = null;
        }
        if (_tag != validTag || _level != validLevel) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _tag = validTag;
              _level = validLevel;
              _page = 0;
            });
            ref
                .read(localProgressProvider.notifier)
                .setWordFilters(tag: validTag, level: validLevel);
          });
        }
        final filtered = filterBase.where((word) {
          final text =
              '${word.enWord} ${word.trMeaning} ${word.pos}'.toLowerCase();
          return matchesWordFilters(word, level: validLevel, tag: validTag) &&
              text.contains(_query.toLowerCase());
        }).toList(growable: false);
        final ordered = orderForPresentation<WordEntry>(
          filtered,
          order: _order,
          hasSearchQuery: _query.isNotEmpty,
          sessionSeed: _shuffleSeed,
          alphabeticalComparator: (left, right) {
            final byWord = left.enWord.toLowerCase().compareTo(
                  right.enWord.toLowerCase(),
                );
            return byWord != 0 ? byWord : left.id.compareTo(right.id);
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
          title: 'Kelimeler',
          subtitle:
              '${items.length} gerçek kelimeyi ara, kartlarla çalış, test çöz veya eşleştir.',
          actions: <Widget>[
            FilledButton.icon(
                onPressed: () => context.go('/words/flashcards'),
                icon: const Icon(Icons.style_rounded),
                label: const Text('Flash Kart')),
            OutlinedButton.icon(
                onPressed: () => context.go('/words/mini-test'),
                icon: const Icon(Icons.quiz_outlined),
                label: const Text('Mini Test')),
            OutlinedButton.icon(
                onPressed: () => context.go('/words/matching'),
                icon: const Icon(Icons.compare_arrows_rounded),
                label: const Text('Eşleştirme')),
            OutlinedButton.icon(
                onPressed: () => context.go('/words/find-word'),
                icon: const Icon(Icons.search_rounded),
                label: const Text('Kelimeyi Bul')),
          ],
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        hintText: 'İngilizce veya Türkçe ara...',
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Aramayı temizle',
                                onPressed: _clearSearch,
                                icon: const Icon(Icons.clear_rounded),
                              )),
                    onChanged: _onSearchChanged),
                const SizedBox(height: 14),
                _TagFilter(
                    tags: tags,
                    selected: validTag,
                    onChanged: (value) {
                      final availableLevels = canonicalWordLevels(
                        filterBase.where(
                          (word) => value == null || word.tags.contains(value),
                        ),
                      );
                      final nextLevel = availableLevels.contains(validLevel)
                          ? validLevel
                          : null;
                      setState(() {
                        _tag = value;
                        _level = nextLevel;
                        _page = 0;
                      });
                      ref
                          .read(localProgressProvider.notifier)
                          .setWordFilters(tag: value, level: nextLevel);
                    }),
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
                    final availableTags = canonicalWordTags(
                      filterBase.where(
                        (word) => value == null || word.level == value,
                      ),
                    );
                    final nextTag =
                        availableTags.contains(validTag) ? validTag : null;
                    setState(() {
                      _level = value;
                      _tag = nextTag;
                      _page = 0;
                    });
                    ref
                        .read(localProgressProvider.notifier)
                        .setWordFilters(tag: nextTag, level: value);
                  },
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final orderControl = SegmentedButton<PresentationOrder>(
                      showSelectedIcon: false,
                      segments: const <ButtonSegment<PresentationOrder>>[
                        ButtonSegment(
                          value: PresentationOrder.mixed,
                          label: Text('Karışık'),
                        ),
                        ButtonSegment(
                          value: PresentationOrder.alphabetical,
                          label: Text('A-Z'),
                        ),
                      ],
                      selected: <PresentationOrder>{_order},
                      onSelectionChanged: (selection) => setState(() {
                        _order = selection.single;
                        _page = 0;
                      }),
                    );
                    final shuffleControl = OutlinedButton.icon(
                      onPressed: _reshuffle,
                      icon: const Icon(Icons.shuffle_rounded, size: 18),
                      label: const Text('Karıştır'),
                    );
                    final translationControl = OutlinedButton.icon(
                      key: const ValueKey<String>('word-translation-toggle'),
                      onPressed: () => setState(
                        () => _showTranslations = !_showTranslations,
                      ),
                      icon: Icon(
                        _showTranslations
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18,
                      ),
                      label: Text(
                        _showTranslations
                            ? 'Çeviriyi gizle'
                            : 'Çeviriyi göster',
                      ),
                    );
                    if (constraints.maxWidth < 520) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: <Widget>[
                              orderControl,
                              shuffleControl,
                            ],
                          ),
                          const SizedBox(height: 8),
                          translationControl,
                        ],
                      );
                    }
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        orderControl,
                        shuffleControl,
                        translationControl,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                FilterChip(
                  key: const ValueKey<String>('word-favorites-filter'),
                  avatar: Icon(
                    _favoritesOnly
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    size: 18,
                  ),
                  label: const Text('Favoriler'),
                  selected: _favoritesOnly,
                  onSelected: (selected) {
                    final nextBase = items
                        .where(
                          (word) =>
                              !selected ||
                              progress.favoriteWordIds.contains(word.id),
                        )
                        .toList(growable: false);
                    var nextTag = validTag;
                    var nextLevel = validLevel;
                    final nextTags = canonicalWordTags(
                      nextBase.where(
                        (word) => nextLevel == null || word.level == nextLevel,
                      ),
                    );
                    if (!nextTags.contains(nextTag)) nextTag = null;
                    final nextLevels = canonicalWordLevels(
                      nextBase.where(
                        (word) =>
                            nextTag == null || word.tags.contains(nextTag),
                      ),
                    );
                    if (!nextLevels.contains(nextLevel)) nextLevel = null;
                    setState(() {
                      _favoritesOnly = selected;
                      _tag = nextTag;
                      _level = nextLevel;
                      _page = 0;
                    });
                    ref.read(localProgressProvider.notifier).setWordFilters(
                          tag: nextTag,
                          level: nextLevel,
                        );
                  },
                ),
                const SizedBox(height: 10),
                Row(children: <Widget>[
                  Expanded(
                    child: Text('${filtered.length} sonuç',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  if (validTag != null || validLevel != null || _favoritesOnly)
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _tag = null;
                          _level = null;
                          _favoritesOnly = false;
                          _page = 0;
                        });
                        ref
                            .read(localProgressProvider.notifier)
                            .setWordFilters();
                      },
                      icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                      label: const Text('Sıfırla'),
                    ),
                ]),
                const SizedBox(height: 2),
                Text('İlerleme bu tarayıcıda saklanır.',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                _Pager(
                  page: page,
                  lastPage: lastPage,
                  onPrevious:
                      page == 0 ? null : () => setState(() => _page = page - 1),
                  onNext: page == lastPage
                      ? null
                      : () => setState(() => _page = page + 1),
                ),
                const SizedBox(height: 8),
                _WordGrid(
                  words: visible,
                  showTranslations: _showTranslations,
                ),
              ]),
        );
      },
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
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

class _TagFilter extends StatelessWidget {
  const _TagFilter(
      {required this.tags, required this.selected, required this.onChanged});
  final List<String> tags;
  final String? selected;
  final ValueChanged<String?> onChanged;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String?>(
        key: ValueKey<String?>(selected),
        initialValue: selected,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Etiket'),
        items: <DropdownMenuItem<String?>>[
          const DropdownMenuItem(value: null, child: Text('Tüm etiketler')),
          ...tags.map(
            (tag) => DropdownMenuItem(value: tag, child: Text(tag)),
          ),
        ],
        onChanged: onChanged,
      );
}

class _WordGrid extends StatelessWidget {
  const _WordGrid({required this.words, required this.showTranslations});
  final List<WordEntry> words;
  final bool showTranslations;
  @override
  Widget build(BuildContext context) {
    if (words.isEmpty) {
      return const SurfaceCard(child: Text('Aramana uygun kelime bulunamadı.'));
    }
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= AppBreakpoints.desktop
          ? 3
          : constraints.maxWidth >= AppBreakpoints.mobileWide
              ? 2
              : 1;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: words.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 156),
        itemBuilder: (context, index) => _WordCard(
          word: words[index],
          showTranslations: showTranslations,
        ),
      );
    });
  }
}

class _WordCard extends ConsumerStatefulWidget {
  const _WordCard({required this.word, required this.showTranslations});
  final WordEntry word;
  final bool showTranslations;

  @override
  ConsumerState<_WordCard> createState() => _WordCardState();
}

class _WordCardState extends ConsumerState<_WordCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final word = widget.word;
    final tokens = AppThemeTokens.of(context);
    final tts = ref.watch(studentTtsControllerProvider);
    final speaking = tts.isSpeaking && tts.activeWordId == word.id;
    final translationVisible = widget.showTranslations || _hovering;
    return MouseRegion(
      onEnter: (_) {
        if (!widget.showTranslations) setState(() => _hovering = true);
      },
      onExit: (_) {
        if (_hovering) setState(() => _hovering = false);
      },
      child: SurfaceCard(
        onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            showDragHandle: false,
            builder: (_) => WordDetailSheet(word: word)),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(spacing: 8, children: <Widget>[
                _Pill(label: word.pos, color: tokens.accentBlue),
                if (word.level != null)
                  _Pill(label: word.level!, color: tokens.hero),
              ]),
              const Spacer(),
              Text(word.enWord,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 5),
              if (translationVisible)
                Text(word.trMeaning,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              Row(children: <Widget>[
                Text('Detayı aç',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: tokens.accent)),
                const Spacer(),
                StudentTtsIconButton(
                  tooltip: 'Kelimeyi dinle',
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  isSpeaking: speaking,
                  isInitializing:
                      tts.isInitializing && tts.activeWordId == word.id,
                  isUnavailable: tts.isUnavailable,
                  onPlay: () => ref
                      .read(studentTtsControllerProvider.notifier)
                      .playWord(word: word),
                  onStop: () =>
                      ref.read(studentTtsControllerProvider.notifier).stop(),
                ),
              ]),
            ]),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(14)),
      child: Text(label,
          style:
              Theme.of(context).textTheme.bodySmall?.copyWith(color: color)));
}

class _WordsLoading extends StatelessWidget {
  const _WordsLoading();
  @override
  Widget build(BuildContext context) => const Center(
      child: Padding(
          padding: EdgeInsets.all(48), child: CircularProgressIndicator()));
}
