import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme_tokens.dart';
import '../../core/content_providers.dart';
import '../../core/local_progress.dart';
import '../../models/test_models.dart';
import '../../repositories/local_progress_repository.dart';
import '../common/page_parts.dart';

class TestExamsPage extends ConsumerWidget {
  const TestExamsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compatibility = ref.watch(testQuestionCompatibilityProvider);
    if (compatibility.isLoading) {
      return const PageFrame(
        title: 'Özgün Testler',
        subtitle: 'Cevaplar doğrulanıyor.',
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (compatibility.hasError) {
      return DataLoadErrorPage(
        message: compatibility.error.toString(),
        onRetry: () => ref.invalidate(testQuestionCompatibilityProvider),
      );
    }
    final exams = ref.watch(testExamsProvider);
    final progress = ref.watch(localProgressProvider);
    return exams.when(
      loading: () => const PageFrame(
          title: 'Özgün Testler',
          subtitle: 'Testler hazırlanıyor.',
          child: Center(child: CircularProgressIndicator())),
      error: (error, _) => DataLoadErrorPage(
          message: error.toString(),
          onRetry: () => ref.invalidate(testExamsProvider)),
      data: (items) {
        final wrong = progress.testQuestionCorrectness.entries
            .where((entry) => !entry.value)
            .length;
        return PageFrame(
          title: 'Özgün Testler',
          subtitle:
              '${items.length} test · Soruların sırası, şıkları ve doğru cevapları Test Bank’tan gelir.',
          actions: <Widget>[
            OutlinedButton.icon(
                onPressed: () => context.go('/tests'),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Testlere dön'))
          ],
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (wrong > 0) ...<Widget>[
                  SurfaceCard(
                      child: Row(children: <Widget>[
                    const Icon(Icons.replay_circle_filled_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text('$wrong yanlış cevap tekrar çözülebilir.')),
                    FilledButton.tonal(
                        onPressed: () => context.go('/tests/wrong'),
                        child: const Text('Yanlışlarımı çöz')),
                  ])),
                  const SizedBox(height: 14),
                ],
                LayoutBuilder(builder: (context, constraints) {
                  final twoColumns = constraints.maxWidth >= 680;
                  final width = twoColumns
                      ? (constraints.maxWidth - 12) / 2
                      : constraints.maxWidth;
                  return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: items
                          .map((exam) => SizedBox(
                                width: width,
                                child: _ExamCard(
                                    exam: exam,
                                    answered: _answeredExamQuestions(
                                        progress, exam.testNo),
                                    best: progress.testExamBestScores[
                                        exam.testNo.toString()],
                                    last: progress.testExamLastScores[
                                        exam.testNo.toString()],
                                    elapsedSeconds:
                                        progress.testExamElapsedSeconds[
                                            exam.testNo.toString()]),
                              ))
                          .toList(growable: false));
                }),
              ]),
        );
      },
    );
  }
}

class _ExamCard extends StatelessWidget {
  const _ExamCard({
    required this.exam,
    required this.answered,
    required this.best,
    required this.last,
    required this.elapsedSeconds,
  });
  final TestExamSummary exam;
  final int answered;
  final int? best;
  final int? last;
  final int? elapsedSeconds;

  @override
  Widget build(BuildContext context) {
    final complete = answered >= exam.questionCount;
    return SurfaceCard(
      onTap: () => context.go('/tests/exam/${exam.testNo}'),
      padding: const EdgeInsets.all(16),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Test ${exam.testNo}',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text('${exam.questionCount} soru',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: answered.clamp(0, exam.questionCount) / exam.questionCount,
            ),
            const SizedBox(height: 6),
            Text('$answered / ${exam.questionCount} cevaplandı',
                style: Theme.of(context).textTheme.bodySmall),
            if (last != null ||
                best != null ||
                elapsedSeconds != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                <String>[
                  if (last != null) 'Son: %$last',
                  if (best != null) 'En iyi: %$best',
                  if (elapsedSeconds != null)
                    'Süre: ${formatTestExamDuration(elapsedSeconds!)}',
                ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            if (!complete)
              FilledButton.tonal(
                onPressed: () => context.go('/tests/exam/${exam.testNo}'),
                child: Text(answered == 0 ? 'Teste başla' : 'Devam et'),
              )
            else
              Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                FilledButton.tonal(
                  onPressed: () => context.go('/tests/exam/${exam.testNo}'),
                  child: const Text('Sonucu incele'),
                ),
                TextButton(
                  onPressed: () =>
                      context.go('/tests/exam/${exam.testNo}?restart=1'),
                  child: const Text('Tekrar çöz'),
                ),
              ]),
          ]),
    );
  }
}

class TestExamPage extends ConsumerStatefulWidget {
  const TestExamPage({
    super.key,
    required this.testNo,
    this.restartRequested = false,
  });
  final int testNo;
  final bool restartRequested;

  @override
  ConsumerState<TestExamPage> createState() => _TestExamPageState();
}

class _TestExamPageState extends ConsumerState<TestExamPage> {
  int? _index;
  bool _restartStarted = false;
  Timer? _timer;
  int _elapsedSeconds = 0;
  bool _clockRestored = false;
  late final LocalProgressController _progressController;

  @override
  void initState() {
    super.initState();
    _progressController = ref.read(localProgressProvider.notifier);
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_clockRestored && _progressController.mounted) {
      _progressController.setTestExamElapsedSeconds(
        testNo: widget.testNo,
        seconds: _elapsedSeconds,
      );
    }
    super.dispose();
  }

  void _syncClock({required int storedSeconds, required bool complete}) {
    if (!_clockRestored) {
      _clockRestored = true;
      if (_elapsedSeconds != storedSeconds) {
        setState(() => _elapsedSeconds = storedSeconds);
      }
    }
    if (complete) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSeconds++);
      if (_elapsedSeconds % 10 == 0) {
        ref.read(localProgressProvider.notifier).setTestExamElapsedSeconds(
              testNo: widget.testNo,
              seconds: _elapsedSeconds,
            );
      }
    });
  }

  void _persistClock() {
    ref.read(localProgressProvider.notifier).setTestExamElapsedSeconds(
          testNo: widget.testNo,
          seconds: _elapsedSeconds,
        );
  }

  @override
  Widget build(BuildContext context) {
    final compatibility = ref.watch(testQuestionCompatibilityProvider);
    final exam = ref.watch(testExamProvider(widget.testNo));
    if (compatibility.isLoading) {
      return const PageFrame(
          title: 'Özgün Test',
          subtitle: 'Cevaplar doğrulanıyor.',
          child: Center(child: CircularProgressIndicator()));
    }
    if (compatibility.hasError) {
      return DataLoadErrorPage(
        message: compatibility.error.toString(),
        onRetry: () => ref.invalidate(testQuestionCompatibilityProvider),
      );
    }
    return exam.when(
      loading: () => const PageFrame(
          title: 'Özgün Test',
          subtitle: 'Sorular hazırlanıyor.',
          child: Center(child: CircularProgressIndicator())),
      error: (error, _) => DataLoadErrorPage(
          message: error.toString(),
          onRetry: () => ref.invalidate(testExamProvider(widget.testNo))),
      data: (data) {
        if (widget.restartRequested && !_restartStarted) {
          _restartStarted = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _restart(data);
          });
          return const PageFrame(
            title: 'Özgün Test',
            subtitle: 'Test yeniden başlatılıyor.',
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final progress = ref.watch(localProgressProvider);
        final restored =
            progress.testExamLastQuestionIndexes[widget.testNo.toString()] ?? 0;
        final index =
            (_index ?? restored).clamp(0, data.questions.length - 1).toInt();
        final question = data.questions[index];
        final answer = progress.testQuestionAnswers[question.id];
        final correct = progress.testQuestionCorrectness[question.id];
        final answered = data.questions
            .where((item) => progress.testQuestionAnswers.containsKey(item.id))
            .length;
        final correctCount = data.questions
            .where((item) => progress.testQuestionCorrectness[item.id] == true)
            .length;
        final complete = answered == data.questions.length;
        final storedSeconds =
            progress.testExamElapsedSeconds[widget.testNo.toString()] ?? 0;
        if (!_clockRestored || (complete && _timer != null)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _syncClock(storedSeconds: storedSeconds, complete: complete);
            }
          });
        }
        if (_index == null && index != restored) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => setState(() => _index = index));
        }
        return PageFrame(
          title: 'Test ${data.testNo}',
          subtitle: complete
              ? 'Tamamlandı · Doğru: $correctCount / ${data.questions.length}'
              : '${index + 1} / ${data.questions.length} soru',
          actions: <Widget>[
            OutlinedButton.icon(
                onPressed: () => context.go('/tests/exams'),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Testlere dön')),
            OutlinedButton.icon(
              onPressed: () => _confirmReset(data),
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('İlerlemeyi sıfırla'),
            ),
          ],
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SurfaceCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: <Widget>[
                          Text('Soru ${index + 1} / ${data.questions.length}',
                              style: Theme.of(context).textTheme.labelLarge),
                          Text(
                              'Cevaplanan $answered / ${data.questions.length}',
                              style: Theme.of(context).textTheme.bodySmall),
                          Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                const Icon(Icons.timer_outlined, size: 16),
                                const SizedBox(width: 4),
                                Text(formatTestExamDuration(_elapsedSeconds),
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                              ]),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                          value: answered / data.questions.length),
                    ],
                  ),
                ),
                if (complete) ...<Widget>[
                  const SizedBox(height: 12),
                  _ExamResultSummary(
                    correct: correctCount,
                    total: data.questions.length,
                    elapsedSeconds: _elapsedSeconds,
                    onWrongAnswers: correctCount == data.questions.length
                        ? null
                        : () => context.go('/tests/wrong'),
                    onRestart: () => _restart(data),
                    onBack: () => context.go('/tests/exams'),
                  ),
                ],
                const SizedBox(height: 12),
                SurfaceCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                      Text('${question.number}. ${question.question}',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      if (answer != null &&
                          question.questionTr.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        Text('Türkçe soru',
                            style: Theme.of(context).textTheme.labelMedium),
                        const SizedBox(height: 3),
                        Text(question.questionTr,
                            style: Theme.of(context).textTheme.bodyMedium),
                      ],
                      const SizedBox(height: 16),
                      for (final option in question.options) ...<Widget>[
                        _ExamOption(
                          option: option,
                          selected: answer == option.textEn,
                          answerKnown: answer != null,
                          isCorrect: option.textEn == question.correctAnswer,
                          onTap: answer == null
                              ? () => _answer(question, option)
                              : null,
                        ),
                        const SizedBox(height: 9),
                      ],
                      if (answer != null) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(correct == true ? 'Doğru cevap' : 'Yanlış cevap',
                            style: TextStyle(
                                color: correct == true
                                    ? AppThemeTokens.of(context).success
                                    : AppThemeTokens.of(context).warning,
                                fontWeight: FontWeight.w800)),
                      ],
                    ])),
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                  OutlinedButton.icon(
                      onPressed: index == 0 ? null : () => _setIndex(index - 1),
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('Önceki')),
                  FilledButton.icon(
                      onPressed: index == data.questions.length - 1
                          ? null
                          : () => _setIndex(index + 1),
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('Sonraki')),
                ]),
              ]),
        );
      },
    );
  }

  void _setIndex(int value) {
    setState(() => _index = value);
    ref
        .read(localProgressProvider.notifier)
        .setTestExamLastQuestion(testNo: widget.testNo, index: value);
  }

  void _answer(TestExamQuestion question, TestExamOption option) {
    final isCorrect = option.textEn == question.correctAnswer;
    final controller = ref.read(localProgressProvider.notifier);
    controller.answerTestQuestion(
      questionId: question.id,
      answer: option.textEn,
      isCorrect: isCorrect,
      contentFingerprint: question.fingerprint,
    );
    final exam = ref.read(testExamProvider(widget.testNo)).valueOrNull;
    if (exam == null) {
      return;
    }
    final correctness = Map<String, bool>.of(
      ref.read(localProgressProvider).testQuestionCorrectness,
    )..[question.id] = isCorrect;
    if (exam.questions.every(correctness.containsKey)) {
      _timer?.cancel();
      _timer = null;
      controller.recordTestExamResult(
        testNo: widget.testNo,
        correct:
            exam.questions.where((item) => correctness[item.id] == true).length,
        total: exam.questions.length,
        elapsedSeconds: _elapsedSeconds,
      );
    } else {
      _persistClock();
    }
  }

  Future<void> _confirmReset(TestExam exam) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Test ${exam.testNo} ilerlemesi sıfırlansın mı?'),
        content: const Text(
          'Bu testin cevapları, puanı ve kaldığınız soru temizlenir. '
          'Diğer testler ve favoriler korunur.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sıfırla'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    _resetProgress(exam);
    setState(() => _index = 0);
  }

  void _restart(TestExam exam) {
    _timer?.cancel();
    _timer = null;
    _elapsedSeconds = 0;
    _clockRestored = false;
    _resetProgress(exam);
    if (!mounted) return;
    context.go('/tests/exam/${exam.testNo}');
  }

  void _resetProgress(TestExam exam) {
    _timer?.cancel();
    _timer = null;
    _elapsedSeconds = 0;
    _clockRestored = false;
    ref.read(localProgressProvider.notifier).resetTestExamProgress(
          testNo: exam.testNo,
          questionIds: exam.questions.map((question) => question.id),
        );
  }
}

String formatTestExamDuration(int seconds) {
  final duration = Duration(seconds: seconds < 0 ? 0 : seconds);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final secs = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours == 0 ? '$minutes:$secs' : '$hours:$minutes:$secs';
}

class _ExamResultSummary extends StatelessWidget {
  const _ExamResultSummary({
    required this.correct,
    required this.total,
    required this.elapsedSeconds,
    required this.onWrongAnswers,
    required this.onRestart,
    required this.onBack,
  });

  final int correct;
  final int total;
  final int elapsedSeconds;
  final VoidCallback? onWrongAnswers;
  final VoidCallback onRestart;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final wrong = total - correct;
    final score = total == 0 ? 0 : ((correct / total) * 100).round();
    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Test sonucu', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: <Widget>[
              Text('Doğru: $correct / $total'),
              Text('Yanlış: $wrong'),
              const Text('Boş: 0'),
              Text('Başarı: %$score'),
              Text('Puan: $score / 100'),
              Text('Süre: ${formatTestExamDuration(elapsedSeconds)}'),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              if (onWrongAnswers != null)
                OutlinedButton.icon(
                  onPressed: onWrongAnswers,
                  icon: const Icon(Icons.replay_rounded),
                  label: const Text('Yanlışları incele'),
                ),
              FilledButton.tonalIcon(
                onPressed: onRestart,
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Testi tekrar çöz'),
              ),
              TextButton(
                onPressed: onBack,
                child: const Text('Testler’e dön'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

int _answeredExamQuestions(LocalProgressSnapshot progress, int testNo) {
  final prefix = 'test-${testNo.toString().padLeft(2, '0')}-q-';
  return progress.testQuestionAnswers.keys
      .where((questionId) => questionId.startsWith(prefix))
      .length;
}

class _ExamOption extends StatelessWidget {
  const _ExamOption(
      {required this.option,
      required this.selected,
      required this.answerKnown,
      required this.isCorrect,
      required this.onTap});
  final TestExamOption option;
  final bool selected;
  final bool answerKnown;
  final bool isCorrect;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final border = answerKnown && isCorrect
        ? tokens.success
        : answerKnown && selected
            ? tokens.warning
            : tokens.surfaceBorder;
    return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.all(14),
            side: BorderSide(
                color: border,
                width: answerKnown && (isCorrect || selected) ? 1.5 : 1),
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('${option.key}. ${option.textEn}',
                    textAlign: TextAlign.left),
                if (answerKnown && option.textTr != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(option.textTr!,
                      textAlign: TextAlign.left,
                      style: Theme.of(context).textTheme.bodySmall)
                ],
              ]),
        ));
  }
}

class TestWrongAnswersPage extends ConsumerStatefulWidget {
  const TestWrongAnswersPage({super.key});

  @override
  ConsumerState<TestWrongAnswersPage> createState() =>
      _TestWrongAnswersPageState();
}

class _TestWrongAnswersPageState extends ConsumerState<TestWrongAnswersPage> {
  @override
  Widget build(BuildContext context) {
    final compatibility = ref.watch(testQuestionCompatibilityProvider);
    if (compatibility.isLoading) {
      return const PageFrame(
        title: 'Yanlışlarım',
        subtitle: 'Cevaplar doğrulanıyor.',
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (compatibility.hasError) {
      return DataLoadErrorPage(
        message: compatibility.error.toString(),
        onRetry: () => ref.invalidate(testQuestionCompatibilityProvider),
      );
    }
    final exams = ref.watch(testExamsProvider);
    return exams.when(
      loading: () => const PageFrame(
          title: 'Yanlışlarım',
          subtitle: 'Sorular hazırlanıyor.',
          child: Center(child: CircularProgressIndicator())),
      error: (error, _) => DataLoadErrorPage(
        message: error.toString(),
        onRetry: () => ref.invalidate(testExamsProvider),
      ),
      data: (summaries) => _WrongListBody(summaries: summaries),
    );
  }
}

class _WrongListBody extends ConsumerStatefulWidget {
  const _WrongListBody({required this.summaries});
  final List<TestExamSummary> summaries;

  @override
  ConsumerState<_WrongListBody> createState() => _WrongListBodyState();
}

class _WrongListBodyState extends ConsumerState<_WrongListBody> {
  Future<List<TestExam>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _loadAll();
  }

  @override
  void didUpdateWidget(covariant _WrongListBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameSummaries(oldWidget.summaries, widget.summaries)) {
      _future = _loadAll();
    }
  }

  bool _sameSummaries(List<TestExamSummary> left, List<TestExamSummary> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index].testNo != right[index].testNo) return false;
    }
    return true;
  }

  Future<List<TestExam>> _loadAll() {
    final repository = ref.read(staticTestRepositoryProvider);
    return Future.wait(widget.summaries
        .map((item) => repository.loadExam(item.testNo))
        .toList(growable: false));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TestExam>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const PageFrame(
              title: 'Yanlışlarım',
              subtitle: 'Sorular hazırlanıyor.',
              child: Center(child: CircularProgressIndicator()));
        }
        final progress = ref.watch(localProgressProvider);
        final wrong = snapshot.data!
            .expand((exam) => exam.questions)
            .where((question) =>
                progress.testQuestionCorrectness[question.id] == false)
            .toList(growable: false);
        return PageFrame(
          title: 'Yanlışlarım',
          subtitle: '${wrong.length} yanlış cevap · Soru sırası korunur.',
          actions: <Widget>[
            OutlinedButton.icon(
                onPressed: () => context.go('/tests/exams'),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Testlere dön'))
          ],
          child: wrong.isEmpty
              ? const SurfaceCard(
                  child: Text('Tekrar çözülecek yanlış cevap yok.'))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: wrong
                      .map((question) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _WrongQuestion(question: question),
                          ))
                      .toList(growable: false)),
        );
      },
    );
  }
}

class _WrongQuestion extends ConsumerWidget {
  const _WrongQuestion({required this.question});
  final TestExamQuestion question;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final answer =
        ref.watch(localProgressProvider).testQuestionAnswers[question.id];
    final correctness =
        ref.watch(localProgressProvider).testQuestionCorrectness[question.id];
    final answered = answer != null;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('${question.id} · ${question.question}',
              style: Theme.of(context).textTheme.titleMedium),
          if (question.questionTr.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(question.questionTr,
                style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: 10),
          for (final option in question.options) ...<Widget>[
            Builder(builder: (context) {
              final selected = answer == option.textEn;
              final isCorrect = option.textEn == question.correctAnswer;
              final tokens = AppThemeTokens.of(context);
              final border = answered && isCorrect
                  ? tokens.success
                  : answered && selected
                      ? tokens.warning
                      : tokens.surfaceBorder;
              return SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => ref
                      .read(localProgressProvider.notifier)
                      .answerTestQuestion(
                        questionId: question.id,
                        answer: option.textEn,
                        isCorrect: option.textEn == question.correctAnswer,
                        contentFingerprint: question.fingerprint,
                      ),
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.all(13),
                    side: BorderSide(
                        color: border,
                        width: answered && (isCorrect || selected) ? 1.5 : 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('${option.key}. ${option.textEn}',
                          textAlign: TextAlign.left),
                      if (answered && option.textTr != null) ...<Widget>[
                        const SizedBox(height: 3),
                        Text(option.textTr!,
                            textAlign: TextAlign.left,
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 7),
          ],
          if (answered) ...<Widget>[
            Text(correctness == true ? 'Doğru cevap' : 'Yanlış cevap',
                style: TextStyle(
                    color: correctness == true
                        ? AppThemeTokens.of(context).success
                        : AppThemeTokens.of(context).warning,
                    fontWeight: FontWeight.w800)),
          ],
        ],
      ),
    );
  }
}
