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

class MatchingPage extends ConsumerStatefulWidget {
  const MatchingPage({super.key});

  @override
  ConsumerState<MatchingPage> createState() => _MatchingPageState();
}

class _MatchingPageState extends ConsumerState<MatchingPage> {
  int _itemCount = practiceItemCountOptions.first;
  int _correct = 0;
  int _wrong = 0;
  int _roundIndex = 0;
  bool _filtersRestored = false;
  String? _level;
  String? _tag;
  String? _sessionKey;
  String? _selectedEnglishId;
  String? _selectedTurkishId;
  bool? _lastAnswerCorrect;
  List<WordEntry> _sessionWords = const <WordEntry>[];
  List<List<WordEntry>> _rounds = const <List<WordEntry>>[];
  List<WordEntry> _englishOrder = const <WordEntry>[];
  List<WordEntry> _turkishOrder = const <WordEntry>[];
  final Set<String> _matchedIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final words = ref.watch(wordsProvider);
    final progress = ref.watch(localProgressProvider);
    _restoreFilters(progress);
    return words.when(
      loading: () => const PageFrame(
        title: 'Eşleştirme',
        subtitle: 'Kelime eşleştirmeleri hazırlanıyor...',
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
        final sessionWords = _sessionFor(
          eligible,
          key: '$validLevel|$validTag|$_itemCount|${allWords.length}',
        );
        final complete = sessionWords.isNotEmpty &&
            _matchedIds.length == sessionWords.length;
        final roundWords =
            _rounds.isEmpty ? const <WordEntry>[] : _rounds[_roundIndex];
        final matchedInRound =
            roundWords.where((word) => _matchedIds.contains(word.id)).length;
        return PageFrame(
          title: 'Eşleştirme',
          subtitle: complete
              ? 'Çalışma tamamlandı'
              : _rounds.isEmpty
                  ? 'Önce çalışma havuzunu seçin.'
                  : 'Tur ${_roundIndex + 1} / ${_rounds.length} · $matchedInRound / ${roundWords.length} eşleştirme',
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
              _MatchingFilters(
                levels: levels,
                tags: tags,
                selectedLevel: validLevel,
                selectedTag: validTag,
                itemCount: _itemCount,
                onLevelChanged: _setLevel,
                onTagChanged: _setTag,
                onCountChanged: _setItemCount,
              ),
              const SizedBox(height: 12),
              Text(
                eligible.length < _itemCount
                    ? '${eligible.length} uygun kelimeden ${sessionWords.length} benzersiz anlamlı eşleştirme hazırlandı.'
                    : '${sessionWords.length} eşleştirme hazırlandı.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 18),
              if (sessionWords.isEmpty)
                _EmptyMatchingPool(onClear: _clearFilters)
              else if (complete)
                _MatchingResult(
                  correct: _correct,
                  wrong: _wrong,
                  onRestart: _restart,
                )
              else ...<Widget>[
                LinearProgressIndicator(
                  value: _matchedIds.length / sessionWords.length,
                  minHeight: 7,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(height: 12),
                if (_lastAnswerCorrect != null) ...<Widget>[
                  _MatchingFeedback(correct: _lastAnswerCorrect!),
                  const SizedBox(height: 12),
                ],
                _MatchingBoard(
                  englishWords: _englishOrder,
                  turkishWords: _turkishOrder,
                  matchedIds: _matchedIds,
                  selectedEnglishId: _selectedEnglishId,
                  selectedTurkishId: _selectedTurkishId,
                  onEnglishSelected: _selectEnglish,
                  onTurkishSelected: _selectTurkish,
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
        _resetSession();
      });
      if (restoredTag != progress.wordTag) {
        ref.read(localProgressProvider.notifier).setWordFilters(
              tag: restoredTag,
              level: progress.wordLevel,
            );
      }
    });
  }

  List<WordEntry> _sessionFor(List<WordEntry> eligible, {required String key}) {
    if (_sessionKey == key) {
      return _sessionWords;
    }
    final random = math.Random();
    final uniqueMeanings = <String>{};
    final shuffled = List<WordEntry>.of(eligible)..shuffle(random);
    _sessionWords = shuffled
        .where(
          (word) => uniqueMeanings.add(word.trMeaning.trim().toLowerCase()),
        )
        .take(_itemCount)
        .toList(growable: false);
    _rounds = splitWordPracticeRounds(_sessionWords);
    _roundIndex = 0;
    _matchedIds.clear();
    _correct = 0;
    _wrong = 0;
    _lastAnswerCorrect = null;
    _selectRound(random);
    _sessionKey = key;
    return _sessionWords;
  }

  void _selectRound(math.Random random) {
    if (_rounds.isEmpty) {
      _englishOrder = const <WordEntry>[];
      _turkishOrder = const <WordEntry>[];
      return;
    }
    final round = _rounds[_roundIndex];
    _englishOrder = List<WordEntry>.of(round)..shuffle(random);
    _turkishOrder = List<WordEntry>.of(round)..shuffle(random);
    _selectedEnglishId = null;
    _selectedTurkishId = null;
  }

  void _selectEnglish(String id) {
    if (_matchedIds.contains(id)) {
      return;
    }
    setState(() {
      _selectedEnglishId = id;
      _lastAnswerCorrect = null;
    });
    _resolvePairIfReady();
  }

  void _selectTurkish(String id) {
    if (_matchedIds.contains(id)) {
      return;
    }
    setState(() {
      _selectedTurkishId = id;
      _lastAnswerCorrect = null;
    });
    _resolvePairIfReady();
  }

  void _resolvePairIfReady() {
    final englishId = _selectedEnglishId;
    final turkishId = _selectedTurkishId;
    if (englishId == null || turkishId == null) {
      return;
    }
    final correct = englishId == turkishId;
    final completedRoundIds =
        _rounds[_roundIndex].map((word) => word.id).toSet();
    setState(() {
      _lastAnswerCorrect = correct;
      if (correct) {
        _matchedIds.add(englishId);
        _correct++;
        _selectedEnglishId = null;
        _selectedTurkishId = null;
        if (completedRoundIds.every(_matchedIds.contains) &&
            _roundIndex < _rounds.length - 1) {
          _roundIndex++;
          _selectRound(math.Random());
        }
      } else {
        _wrong++;
        _selectedTurkishId = null;
      }
    });
    if (correct) {
      ref.read(localProgressProvider.notifier).markWordKnown(englishId);
    }
  }

  void _setLevel(String? value) => _applyFilters(level: value, tag: _tag);

  void _setTag(String? value) => _applyFilters(level: _level, tag: value);

  void _setItemCount(int? value) {
    if (value == null || value == _itemCount) {
      return;
    }
    setState(() {
      _itemCount = value;
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

  void _restart() => setState(_resetSession);

  void _resetSession() {
    _correct = 0;
    _wrong = 0;
    _roundIndex = 0;
    _lastAnswerCorrect = null;
    _selectedEnglishId = null;
    _selectedTurkishId = null;
    _matchedIds.clear();
    _sessionKey = null;
    _sessionWords = const <WordEntry>[];
    _rounds = const <List<WordEntry>>[];
    _englishOrder = const <WordEntry>[];
    _turkishOrder = const <WordEntry>[];
  }
}

class _MatchingFilters extends StatelessWidget {
  const _MatchingFilters({
    required this.levels,
    required this.tags,
    required this.selectedLevel,
    required this.selectedTag,
    required this.itemCount,
    required this.onLevelChanged,
    required this.onTagChanged,
    required this.onCountChanged,
  });

  final List<String> levels;
  final List<String> tags;
  final String? selectedLevel;
  final String? selectedTag;
  final int itemCount;
  final ValueChanged<String?> onLevelChanged;
  final ValueChanged<String?> onTagChanged;
  final ValueChanged<int?> onCountChanged;

  @override
  Widget build(BuildContext context) => Column(
        children: <Widget>[
          DropdownButtonFormField<String?>(
            key: ValueKey<String?>('matching-level-$selectedLevel'),
            initialValue: selectedLevel,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Seviye'),
            items: <DropdownMenuItem<String?>>[
              const DropdownMenuItem(
                value: null,
                child: Text('Tüm seviyeler'),
              ),
              ...levels.map(
                (level) => DropdownMenuItem(value: level, child: Text(level)),
              ),
            ],
            onChanged: onLevelChanged,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            key: ValueKey<String?>('matching-tag-$selectedTag'),
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
            key: ValueKey<int>(itemCount),
            initialValue: itemCount,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Çalışma sayısı'),
            items: practiceItemCountOptions
                .map(
                  (count) => DropdownMenuItem(
                    value: count,
                    child: Text('$count eşleştirme'),
                  ),
                )
                .toList(growable: false),
            onChanged: onCountChanged,
          ),
        ],
      );
}

class _MatchingBoard extends StatelessWidget {
  const _MatchingBoard({
    required this.englishWords,
    required this.turkishWords,
    required this.matchedIds,
    required this.selectedEnglishId,
    required this.selectedTurkishId,
    required this.onEnglishSelected,
    required this.onTurkishSelected,
  });

  final List<WordEntry> englishWords;
  final List<WordEntry> turkishWords;
  final Set<String> matchedIds;
  final String? selectedEnglishId;
  final String? selectedTurkishId;
  final ValueChanged<String> onEnglishSelected;
  final ValueChanged<String> onTurkishSelected;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _MatchingColumn(
                title: 'İngilizce',
                words: englishWords,
                matchedIds: matchedIds,
                selectedId: selectedEnglishId,
                useTurkish: false,
                onSelected: onEnglishSelected,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MatchingColumn(
                title: 'Türkçe anlam',
                words: turkishWords,
                matchedIds: matchedIds,
                selectedId: selectedTurkishId,
                useTurkish: true,
                onSelected: onTurkishSelected,
              ),
            ),
          ],
        ),
      );
}

class _MatchingColumn extends StatelessWidget {
  const _MatchingColumn({
    required this.title,
    required this.words,
    required this.matchedIds,
    required this.selectedId,
    required this.useTurkish,
    required this.onSelected,
  });

  final String title;
  final List<WordEntry> words;
  final Set<String> matchedIds;
  final String? selectedId;
  final bool useTurkish;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final remaining = words.where((word) => !matchedIds.contains(word.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final word in remaining) ...<Widget>[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => onSelected(word.id),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                minimumSize: const Size(0, 42),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                backgroundColor: selectedId == word.id
                    ? tokens.accent.withValues(alpha: .14)
                    : null,
              ),
              child: Text(
                useTurkish ? word.trMeaning : word.enWord,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.left,
              ),
            ),
          ),
          const SizedBox(height: 7),
        ],
      ],
    );
  }
}

class _MatchingFeedback extends StatelessWidget {
  const _MatchingFeedback({required this.correct});

  final bool correct;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color:
            (correct ? tokens.success : tokens.warning).withValues(alpha: .12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        correct ? 'Doğru eşleştirme.' : 'Bu eşleşme doğru değil; tekrar dene.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

class _EmptyMatchingPool extends StatelessWidget {
  const _EmptyMatchingPool({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.filter_alt_off_rounded, size: 30),
            const SizedBox(height: 10),
            Text(
              'Bu filtrelerle eşleştirme için kelime yok.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text('Filtreleri değiştir veya tüm kelimelere dön.'),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              key: const ValueKey<String>('matching-clear-filters'),
              onPressed: onClear,
              icon: const Icon(Icons.filter_alt_off_rounded),
              label: const Text('Filtreleri temizle'),
            ),
          ],
        ),
      );
}

class _MatchingResult extends StatelessWidget {
  const _MatchingResult({
    required this.correct,
    required this.wrong,
    required this.onRestart,
  });

  final int correct;
  final int wrong;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final total = correct + wrong;
    final ratio = total == 0 ? 0 : ((correct / total) * 100).round();
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Başarı: %$ratio',
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 10),
          Text('Doğru: $correct · Yanlış: $wrong'),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onRestart,
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Yeni tur'),
          ),
        ],
      ),
    );
  }
}
