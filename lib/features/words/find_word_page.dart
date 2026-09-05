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

class FindWordPage extends ConsumerStatefulWidget {
  const FindWordPage({super.key});

  @override
  ConsumerState<FindWordPage> createState() => _FindWordPageState();
}

class _FindWordPageState extends ConsumerState<FindWordPage> {
  int _questionCount = practiceItemCountOptions.first;
  int _questionIndex = 0;
  int _correct = 0;
  int? _selected;
  bool _showDetails = false;
  bool _filtersRestored = false;
  String? _level;
  String? _tag;
  String? _questionsKey;
  List<_FindQuestion> _questions = const <_FindQuestion>[];
  final List<WordEntry> _incorrectWords = <WordEntry>[];

  @override
  Widget build(BuildContext context) {
    final words = ref.watch(wordsProvider);
    final progress = ref.watch(localProgressProvider);
    _restoreFilters(progress);
    return words.when(
      loading: () => const PageFrame(
        title: 'Kelimeyi Bul',
        subtitle: 'Sorular hazırlanıyor...',
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
        final questions = _questionsFor(
          eligible,
          allWords,
          key: '$validLevel|$validTag|$_questionCount|${allWords.length}',
        );
        final complete =
            questions.isNotEmpty && _questionIndex >= questions.length;
        return PageFrame(
          title: 'Kelimeyi Bul',
          subtitle: complete
              ? 'Çalışma tamamlandı'
              : questions.isEmpty
                  ? 'Önce çalışma havuzunu seçin.'
                  : 'Soru ${_questionIndex + 1} / ${questions.length}',
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
              _FindWordFilters(
                levels: levels,
                tags: tags,
                selectedLevel: validLevel,
                selectedTag: validTag,
                questionCount: _questionCount,
                onLevelChanged: _setLevel,
                onTagChanged: _setTag,
                onCountChanged: _setQuestionCount,
              ),
              const SizedBox(height: 12),
              Text(
                eligible.length < _questionCount
                    ? '${eligible.length} uygun kelime bulundu; ${questions.length} soru hazırlanacak.'
                    : '${eligible.length} uygun kelimeden ${questions.length} soru hazırlandı.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 18),
              if (questions.isEmpty)
                _EmptyFindWordPool(onClear: _clearFilters)
              else if (complete)
                _FindWordResult(
                  correct: _correct,
                  total: questions.length,
                  incorrectWords: _incorrectWords,
                  onRestart: _restart,
                )
              else
                _FindWordQuestionCard(
                  question: questions[_questionIndex],
                  selected: _selected,
                  showDetails: _showDetails,
                  onToggleDetails: () => setState(
                    () => _showDetails = !_showDetails,
                  ),
                  onAnswer: _selected == null
                      ? (index) => _answer(questions[_questionIndex], index)
                      : null,
                  onNext: _selected == null ? null : _next,
                  isLast: _questionIndex == questions.length - 1,
                ),
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

  List<_FindQuestion> _questionsFor(
    List<WordEntry> eligible,
    List<WordEntry> allWords, {
    required String key,
  }) {
    if (_questionsKey == key) {
      return _questions;
    }
    _questions = _makeFindWordQuestions(
      eligible,
      allWords,
      questionCount: _questionCount,
    );
    _questionsKey = key;
    return _questions;
  }

  void _answer(_FindQuestion question, int selected) {
    final correct = selected == question.correctIndex;
    setState(() {
      _selected = selected;
      if (correct) {
        _correct++;
      } else if (!_incorrectWords.any((word) => word.id == question.word.id)) {
        _incorrectWords.add(question.word);
      }
    });
    if (correct) {
      ref.read(localProgressProvider.notifier).markWordKnown(question.word.id);
    }
  }

  void _next() => setState(() {
        _questionIndex++;
        _selected = null;
        _showDetails = false;
      });

  void _restart() => setState(_resetSession);

  void _setLevel(String? value) => _applyFilters(level: value, tag: _tag);

  void _setTag(String? value) => _applyFilters(level: _level, tag: value);

  void _setQuestionCount(int? value) {
    if (value == null || value == _questionCount) {
      return;
    }
    setState(() {
      _questionCount = value;
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
    _questionIndex = 0;
    _correct = 0;
    _selected = null;
    _showDetails = false;
    _questionsKey = null;
    _questions = const <_FindQuestion>[];
    _incorrectWords.clear();
  }
}

List<_FindQuestion> _makeFindWordQuestions(
  List<WordEntry> eligible,
  List<WordEntry> allWords, {
  required int questionCount,
}) {
  if (eligible.isEmpty) {
    return const <_FindQuestion>[];
  }
  final random = math.Random();
  final words = List<WordEntry>.of(eligible)..shuffle(random);
  final questions = <_FindQuestion>[];
  for (final word in words.take(questionCount)) {
    final direction = questions.length.isEven
        ? _FindDirection.englishToTurkish
        : _FindDirection.turkishToEnglish;
    final options = _findOptions(
      word,
      allWords,
      direction: direction,
      random: random,
    );
    if (options.length < 2) {
      continue;
    }
    questions.add(
      _FindQuestion(
        word: word,
        direction: direction,
        options: options,
        correctIndex: options.indexWhere((option) => option.word.id == word.id),
      ),
    );
  }
  return questions;
}

List<_FindOption> _findOptions(
  WordEntry word,
  List<WordEntry> allWords, {
  required _FindDirection direction,
  required math.Random random,
}) {
  final options = <_FindOption>[_FindOption(word)];
  final seen = <String>{_optionKey(word, direction)};
  final sameLevel = allWords.where(
    (item) => item.id != word.id && item.level == word.level,
  );
  final fallback = allWords.where((item) => item.id != word.id);
  for (final candidates in <Iterable<WordEntry>>[sameLevel, fallback]) {
    final shuffled = List<WordEntry>.of(candidates)..shuffle(random);
    for (final candidate in shuffled) {
      if (seen.add(_optionKey(candidate, direction))) {
        options.add(_FindOption(candidate));
      }
      if (options.length == 4) {
        break;
      }
    }
    if (options.length == 4) {
      break;
    }
  }
  options.shuffle(random);
  return options;
}

String _optionKey(WordEntry word, _FindDirection direction) =>
    direction == _FindDirection.englishToTurkish
        ? word.trMeaning.trim().toLowerCase()
        : word.enWord.trim().toLowerCase();

enum _FindDirection { englishToTurkish, turkishToEnglish }

class _FindQuestion {
  const _FindQuestion({
    required this.word,
    required this.direction,
    required this.options,
    required this.correctIndex,
  });

  final WordEntry word;
  final _FindDirection direction;
  final List<_FindOption> options;
  final int correctIndex;

  String get prompt => direction == _FindDirection.englishToTurkish
      ? word.enWord
      : word.trMeaning;

  String get promptLabel => direction == _FindDirection.englishToTurkish
      ? 'İNGİLİZCE KELİME'
      : 'TÜRKÇE ANLAM';

  String get instruction => direction == _FindDirection.englishToTurkish
      ? 'Doğru Türkçe anlamı seç.'
      : 'Doğru İngilizce kelimeyi seç.';

  String optionText(_FindOption option) =>
      direction == _FindDirection.englishToTurkish
          ? option.word.trMeaning
          : option.word.enWord;
}

class _FindOption {
  const _FindOption(this.word);

  final WordEntry word;
}

class _FindWordFilters extends StatelessWidget {
  const _FindWordFilters({
    required this.levels,
    required this.tags,
    required this.selectedLevel,
    required this.selectedTag,
    required this.questionCount,
    required this.onLevelChanged,
    required this.onTagChanged,
    required this.onCountChanged,
  });

  final List<String> levels;
  final List<String> tags;
  final String? selectedLevel;
  final String? selectedTag;
  final int questionCount;
  final ValueChanged<String?> onLevelChanged;
  final ValueChanged<String?> onTagChanged;
  final ValueChanged<int?> onCountChanged;

  @override
  Widget build(BuildContext context) => Column(
        children: <Widget>[
          DropdownButtonFormField<String?>(
            key: ValueKey<String?>('find-word-level-$selectedLevel'),
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
            key: ValueKey<String?>('find-word-tag-$selectedTag'),
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
            key: ValueKey<int>(questionCount),
            initialValue: questionCount,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Soru sayısı'),
            items: practiceItemCountOptions
                .map(
                  (count) => DropdownMenuItem(
                    value: count,
                    child: Text('$count soru'),
                  ),
                )
                .toList(growable: false),
            onChanged: onCountChanged,
          ),
        ],
      );
}

class _FindWordQuestionCard extends StatelessWidget {
  const _FindWordQuestionCard({
    required this.question,
    required this.selected,
    required this.showDetails,
    required this.onToggleDetails,
    required this.onAnswer,
    required this.onNext,
    required this.isLast,
  });

  final _FindQuestion question;
  final int? selected;
  final bool showDetails;
  final VoidCallback onToggleDetails;
  final ValueChanged<int>? onAnswer;
  final VoidCallback? onNext;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final answeredCorrectly = selected == question.correctIndex;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            question.promptLabel,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: tokens.secondaryText,
                  letterSpacing: 1.1,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            question.prompt,
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 8),
          Text(question.instruction,
              style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 22),
          for (var index = 0;
              index < question.options.length;
              index++) ...<Widget>[
            _FindChoice(
              label: question.optionText(question.options[index]),
              selected: selected == index,
              correct: selected == null ? null : index == question.correctIndex,
              onTap: onAnswer == null ? null : () => onAnswer!(index),
            ),
            const SizedBox(height: 10),
          ],
          OutlinedButton.icon(
            key: const ValueKey<String>('find-word-details'),
            onPressed: onToggleDetails,
            icon: Icon(
              showDetails
                  ? Icons.expand_less_rounded
                  : Icons.info_outline_rounded,
            ),
            label: Text(showDetails ? 'Ayrıntıyı gizle' : 'Ayrıntı'),
          ),
          if (showDetails) ...<Widget>[
            const SizedBox(height: 10),
            _FindWordDetails(word: question.word),
          ],
          if (selected != null) ...<Widget>[
            const SizedBox(height: 14),
            Text(
              answeredCorrectly
                  ? 'Doğru! ${question.word.enWord} — ${question.word.trMeaning}'
                  : 'Doğru cevap: ${question.word.enWord} — ${question.word.trMeaning}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: answeredCorrectly ? tokens.success : tokens.warning,
                  ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onNext,
              child: Text(isLast ? 'Sonucu gör' : 'Sonraki soru'),
            ),
          ],
        ],
      ),
    );
  }
}

class _FindChoice extends StatelessWidget {
  const _FindChoice({
    required this.label,
    required this.selected,
    required this.correct,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool? correct;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final color = correct == null
        ? (selected ? tokens.accent : tokens.surfaceMuted)
        : correct!
            ? tokens.success
            : selected
                ? tokens.warning
                : tokens.surfaceMuted;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          backgroundColor: color.withValues(
            alpha: correct == null && !selected ? .45 : .18,
          ),
          side: BorderSide(color: color),
          minimumSize: const Size(0, 48),
        ),
        child: Text(label),
      ),
    );
  }
}

class _FindWordDetails extends StatelessWidget {
  const _FindWordDetails({required this.word});

  final WordEntry word;

  @override
  Widget build(BuildContext context) {
    final values = <(String, String)>[
      if (_notBlank(word.synonymsRaw)) ('Eş anlamlılar', word.synonymsRaw!),
      if (_notBlank(word.antonymsRaw)) ('Zıt anlamlılar', word.antonymsRaw!),
      if (_notBlank(word.exampleEn)) ('Örnek', word.exampleEn),
      if (_notBlank(word.exampleTr)) ('Çeviri', word.exampleTr!),
    ];
    if (values.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AppThemeTokens.of(context).surfaceMuted.withValues(alpha: .45),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final value in values) ...<Widget>[
            Text(
              '${value.$1}:',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            Text(value.$2),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _EmptyFindWordPool extends StatelessWidget {
  const _EmptyFindWordPool({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.filter_alt_off_rounded, size: 30),
            const SizedBox(height: 10),
            Text(
              'Bu filtrelerle soru için kelime yok.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text('Filtreleri değiştir veya tüm kelimelere dön.'),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              key: const ValueKey<String>('find-word-clear-filters'),
              onPressed: onClear,
              icon: const Icon(Icons.filter_alt_off_rounded),
              label: const Text('Filtreleri temizle'),
            ),
          ],
        ),
      );
}

class _FindWordResult extends StatelessWidget {
  const _FindWordResult({
    required this.correct,
    required this.total,
    required this.incorrectWords,
    required this.onRestart,
  });

  final int correct;
  final int total;
  final List<WordEntry> incorrectWords;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final wrong = total - correct;
    final ratio = ((correct / total) * 100).round();
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
          if (incorrectWords.isNotEmpty) ...<Widget>[
            const SizedBox(height: 20),
            Text(
              'Yanlış yapılan kelimeler',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final word in incorrectWords)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('${word.enWord} — ${word.trMeaning}'),
              ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onRestart,
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Yeni çalışma'),
          ),
        ],
      ),
    );
  }
}

bool _notBlank(String? value) => value?.trim().isNotEmpty ?? false;
