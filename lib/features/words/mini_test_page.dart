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

class MiniTestPage extends ConsumerStatefulWidget {
  const MiniTestPage({super.key});

  @override
  ConsumerState<MiniTestPage> createState() => _MiniTestPageState();
}

class _MiniTestPageState extends ConsumerState<MiniTestPage> {
  int _questionIndex = 0;
  int _correct = 0;
  int _questionCount = practiceItemCountOptions.first;
  int? _selected;
  bool _filtersRestored = false;
  String? _level;
  String? _tag;
  String? _questionsKey;
  List<_TestQuestion> _questions = const <_TestQuestion>[];

  @override
  Widget build(BuildContext context) {
    final words = ref.watch(wordsProvider);
    final progress = ref.watch(localProgressProvider);
    _restoreFilters(progress);
    return words.when(
      loading: () => const PageFrame(
        title: 'Mini test',
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
          title: 'Mini test',
          subtitle: complete
              ? 'Test tamamlandı'
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
              _MiniTestFilters(
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
                _EmptyTestPool(onClear: _clearFilters)
              else if (complete)
                _ResultPanel(
                  correct: _correct,
                  total: questions.length,
                  onRestart: _restart,
                )
              else
                _QuestionCard(
                  question: questions[_questionIndex],
                  selected: _selected,
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
        _resetQuiz();
      });
      if (restoredTag != progress.wordTag) {
        ref.read(localProgressProvider.notifier).setWordFilters(
              tag: restoredTag,
              level: progress.wordLevel,
            );
      }
    });
  }

  List<_TestQuestion> _questionsFor(
    List<WordEntry> eligible,
    List<WordEntry> allWords, {
    required String key,
  }) {
    if (_questionsKey == key) {
      return _questions;
    }
    _questions = _makeMiniTestQuestions(
      eligible,
      allWords,
      questionCount: _questionCount,
    );
    _questionsKey = key;
    return _questions;
  }

  void _answer(_TestQuestion question, int selected) {
    setState(() {
      _selected = selected;
      if (selected == question.correctIndex) {
        _correct++;
      }
    });
    if (selected == question.correctIndex) {
      ref.read(localProgressProvider.notifier).markWordKnown(question.word.id);
    }
  }

  void _next() => setState(() {
        _questionIndex++;
        _selected = null;
      });

  void _restart() => setState(_resetQuiz);

  void _setLevel(String? value) => _applyFilters(level: value, tag: _tag);

  void _setTag(String? value) => _applyFilters(level: _level, tag: value);

  void _setQuestionCount(int? value) {
    if (value == null || value == _questionCount) {
      return;
    }
    setState(() {
      _questionCount = value;
      _resetQuiz();
    });
  }

  void _clearFilters() => _applyFilters(level: null, tag: null);

  void _applyFilters({required String? level, required String? tag}) {
    setState(() {
      _level = level;
      _tag = tag;
      _resetQuiz();
    });
    ref.read(localProgressProvider.notifier).setWordFilters(
          tag: tag,
          level: level,
        );
  }

  void _resetQuiz() {
    _questionIndex = 0;
    _correct = 0;
    _selected = null;
    _questionsKey = null;
    _questions = const <_TestQuestion>[];
  }
}

List<_TestQuestion> _makeMiniTestQuestions(
  List<WordEntry> eligible,
  List<WordEntry> allWords, {
  required int questionCount,
}) {
  if (eligible.isEmpty) {
    return const <_TestQuestion>[];
  }
  final random = math.Random();
  final candidates = List<WordEntry>.of(eligible)..shuffle(random);
  final questions = <_TestQuestion>[];
  for (final word in candidates.take(questionCount)) {
    final distractorMeanings = <String>{};
    final distractors = <WordEntry>[];
    for (final item in List<WordEntry>.of(allWords)..shuffle(random)) {
      if (item.id == word.id || item.trMeaning == word.trMeaning) {
        continue;
      }
      if (distractorMeanings.add(item.trMeaning)) {
        distractors.add(item);
      }
      if (distractors.length == 3) {
        break;
      }
    }
    if (distractors.isEmpty) {
      continue;
    }
    final options = <String>[
      word.trMeaning,
      ...distractors.map((item) => item.trMeaning),
    ]..shuffle(random);
    questions.add(
      _TestQuestion(
        word: word,
        options: options,
        correctIndex: options.indexOf(word.trMeaning),
      ),
    );
  }
  return questions;
}

class _MiniTestFilters extends StatelessWidget {
  const _MiniTestFilters({
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
            key: ValueKey<String?>('mini-test-level-$selectedLevel'),
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
            key: ValueKey<String?>('mini-test-tag-$selectedTag'),
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

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.question,
    required this.selected,
    required this.onAnswer,
    required this.onNext,
    required this.isLast,
  });

  final _TestQuestion question;
  final int? selected;
  final ValueChanged<int>? onAnswer;
  final VoidCallback? onNext;
  final bool isLast;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              question.word.enWord,
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Doğru Türkçe anlamını seç.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 22),
            for (var index = 0;
                index < question.options.length;
                index++) ...<Widget>[
              _ChoiceButton(
                label: question.options[index],
                selected: selected == index,
                correct:
                    selected == null ? null : index == question.correctIndex,
                onTap: onAnswer == null ? null : () => onAnswer!(index),
              ),
              const SizedBox(height: 10),
            ],
            if (selected != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                selected == question.correctIndex
                    ? 'Doğru! ${question.word.trMeaning}'
                    : 'Doğru cevap: ${question.word.trMeaning}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: selected == question.correctIndex
                          ? AppThemeTokens.of(context).success
                          : AppThemeTokens.of(context).warning,
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

class _EmptyTestPool extends StatelessWidget {
  const _EmptyTestPool({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.filter_alt_off_rounded, size: 30),
            const SizedBox(height: 10),
            Text(
              'Bu filtrelerle test için kelime yok.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text('Filtreleri değiştir veya tüm kelimelere dön.'),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              key: const ValueKey<String>('mini-test-clear-filters'),
              onPressed: onClear,
              icon: const Icon(Icons.filter_alt_off_rounded),
              label: const Text('Filtreleri temizle'),
            ),
          ],
        ),
      );
}

class _TestQuestion {
  const _TestQuestion({
    required this.word,
    required this.options,
    required this.correctIndex,
  });

  final WordEntry word;
  final List<String> options;
  final int correctIndex;
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
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
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          backgroundColor: color.withValues(
            alpha: correct == null && !selected ? .45 : .18,
          ),
          side: BorderSide(color: color),
        ),
        onPressed: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(label),
        ),
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({
    required this.correct,
    required this.total,
    required this.onRestart,
  });

  final int correct;
  final int total;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Skorun: %${((correct / total) * 100).round()}',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 10),
            Text('$correct / $total doğru'),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRestart,
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Yeni test'),
            ),
          ],
        ),
      );
}
