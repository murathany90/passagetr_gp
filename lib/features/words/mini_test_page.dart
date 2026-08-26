import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme_tokens.dart';
import '../../core/content_providers.dart';
import '../../models/content_models.dart';
import '../common/page_parts.dart';

class MiniTestPage extends ConsumerStatefulWidget {
  const MiniTestPage({super.key, this.packId});
  final String? packId;
  @override
  ConsumerState<MiniTestPage> createState() => _MiniTestPageState();
}

class _MiniTestPageState extends ConsumerState<MiniTestPage> {
  int _questionIndex = 0;
  int _correct = 0;
  int? _selected;
  List<_TestQuestion> _questions = <_TestQuestion>[];

  @override
  Widget build(BuildContext context) {
    final words = ref.watch(wordsProvider);
    return words.when(
      loading: () => const PageFrame(
          title: 'Mini test',
          subtitle: 'Sorular hazırlanıyor...',
          child: Center(child: CircularProgressIndicator())),
      error: (error, _) => DataLoadErrorPage(
          message: error.toString(),
          onRetry: () => ref.invalidate(wordsProvider)),
      data: (allWords) {
        _questions = _questions.isEmpty
            ? _makeQuestions(allWords, widget.packId)
            : _questions;
        if (_questions.isEmpty) {
          return const DataLoadErrorPage(
              message: 'DATA_LOAD_ERROR: Test için yeterli kelime bulunamadı.');
        }
        if (_questionIndex >= _questions.length) {
          return _ResultPage(
              correct: _correct, total: _questions.length, onRestart: _restart);
        }
        final question = _questions[_questionIndex];
        return PageFrame(
          title: 'Mini test',
          subtitle: 'Soru ${_questionIndex + 1} / ${_questions.length}',
          actions: <Widget>[
            OutlinedButton.icon(
                onPressed: () => context.go('/words'),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Kelimelere dön'))
          ],
          child: SurfaceCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                Text(question.word.enWord,
                    style: Theme.of(context).textTheme.displaySmall),
                const SizedBox(height: 8),
                Text('Doğru Türkçe anlamını seç.',
                    style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 22),
                for (var index = 0;
                    index < question.options.length;
                    index++) ...<Widget>[
                  _ChoiceButton(
                      label: question.options[index],
                      selected: _selected == index,
                      correct: _selected == null
                          ? null
                          : index == question.correctIndex,
                      onTap: _selected == null
                          ? () => _answer(question, index)
                          : null),
                  const SizedBox(height: 10),
                ],
                if (_selected != null) ...<Widget>[
                  const SizedBox(height: 12),
                  FilledButton(
                      onPressed: _next,
                      child: Text(_questionIndex == _questions.length - 1
                          ? 'Sonucu gör'
                          : 'Sonraki soru')),
                ],
              ])),
        );
      },
    );
  }

  void _answer(_TestQuestion question, int selected) => setState(() {
        _selected = selected;
        if (selected == question.correctIndex) {
          _correct++;
        }
      });
  void _next() => setState(() {
        _questionIndex++;
        _selected = null;
      });
  void _restart() => setState(() {
        _questionIndex = 0;
        _correct = 0;
        _selected = null;
        _questions = <_TestQuestion>[];
      });
}

List<_TestQuestion> _makeQuestions(List<WordEntry> allWords, String? packId) {
  final pool = allWords
      .where((word) => packId == null || word.packId == packId)
      .toList(growable: false);
  if (pool.length < 4) {
    return const <_TestQuestion>[];
  }
  final random = math.Random(143);
  final candidates = List<WordEntry>.of(pool)..shuffle(random);
  return candidates.take(math.min(10, candidates.length)).map((word) {
    final distractors = allWords
        .where((item) => item.id != word.id && item.trMeaning != word.trMeaning)
        .toList(growable: false)
      ..shuffle(random);
    final options = <String>[
      word.trMeaning,
      ...distractors.take(3).map((item) => item.trMeaning)
    ]..shuffle(random);
    return _TestQuestion(
        word: word,
        options: options,
        correctIndex: options.indexOf(word.trMeaning));
  }).toList(growable: false);
}

class _TestQuestion {
  const _TestQuestion(
      {required this.word, required this.options, required this.correctIndex});
  final WordEntry word;
  final List<String> options;
  final int correctIndex;
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton(
      {required this.label,
      required this.selected,
      required this.correct,
      required this.onTap});
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
                  alpha: correct == null && !selected ? .45 : .18),
              side: BorderSide(color: color)),
          onPressed: onTap,
          child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(label)),
        ));
  }
}

class _ResultPage extends StatelessWidget {
  const _ResultPage(
      {required this.correct, required this.total, required this.onRestart});
  final int correct;
  final int total;
  final VoidCallback onRestart;
  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'Test tamamlandı',
        subtitle: '$correct / $total doğru',
        child: SurfaceCard(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
              Text('Skorun: %${((correct / total) * 100).round()}',
                  style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 16),
              Text('Sonuç yalnızca bu açık oturum için gösterilir.',
                  style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 20),
              FilledButton.icon(
                  onPressed: onRestart,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Yeni test')),
            ])),
      );
}
