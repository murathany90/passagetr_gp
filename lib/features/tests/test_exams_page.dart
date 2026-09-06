import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme_tokens.dart';
import '../../core/content_providers.dart';
import '../../core/local_progress.dart';
import '../../models/test_models.dart';
import '../common/page_parts.dart';

class TestExamsPage extends ConsumerWidget {
  const TestExamsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exams = ref.watch(testExamsProvider);
    final progress = ref.watch(localProgressProvider);
    return exams.when(
      loading: () => const PageFrame(
          title: 'Özgün Testler',
          subtitle: 'Canonical testler hazırlanıyor.',
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
                                    best: progress.testExamBestScores[
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
  const _ExamCard({required this.exam, required this.best});
  final TestExamSummary exam;
  final int? best;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        onTap: () => context.go('/tests/exam/${exam.testNo}'),
        padding: const EdgeInsets.all(16),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Test ${exam.testNo}',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text('${exam.questionCount} canonical soru',
                  style: Theme.of(context).textTheme.bodyMedium),
              if (best != null) ...<Widget>[
                const SizedBox(height: 6),
                Text('En iyi sonuç: %$best',
                    style: Theme.of(context).textTheme.bodySmall)
              ],
              const SizedBox(height: 12),
              FilledButton.tonal(
                  onPressed: () => context.go('/tests/exam/${exam.testNo}'),
                  child: const Text('Teste başla')),
            ]),
      );
}

class TestExamPage extends ConsumerStatefulWidget {
  const TestExamPage({super.key, required this.testNo});
  final int testNo;

  @override
  ConsumerState<TestExamPage> createState() => _TestExamPageState();
}

class _TestExamPageState extends ConsumerState<TestExamPage> {
  int? _index;

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
    return exam.when(
      loading: () => const PageFrame(
          title: 'Özgün Test',
          subtitle: 'Sorular hazırlanıyor.',
          child: Center(child: CircularProgressIndicator())),
      error: (error, _) => DataLoadErrorPage(
          message: error.toString(),
          onRetry: () => ref.invalidate(testExamProvider(widget.testNo))),
      data: (data) {
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
                label: const Text('Testlere dön'))
          ],
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                LinearProgressIndicator(
                    value: (index + 1) / data.questions.length),
                const SizedBox(height: 16),
                SurfaceCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                      Text('${question.number}. ${question.question}',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700)),
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
      controller.setTestExamBestScore(
        testNo: widget.testNo,
        correct:
            exam.questions.where((item) => correctness[item.id] == true).length,
        total: exam.questions.length,
      );
    }
  }
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
                if (option.textTr != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(option.textTr!,
                      textAlign: TextAlign.left,
                      style: Theme.of(context).textTheme.bodySmall)
                ],
              ]),
        ));
  }
}

class TestWrongAnswersPage extends ConsumerWidget {
  const TestWrongAnswersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exams = ref.watch(testExamsProvider);
    final progress = ref.watch(localProgressProvider);
    return exams.when(
      loading: () => const PageFrame(
          title: 'Yanlışlarım',
          subtitle: 'Sorular hazırlanıyor.',
          child: Center(child: CircularProgressIndicator())),
      error: (error, _) => DataLoadErrorPage(message: error.toString()),
      data: (summaries) => FutureBuilder<List<TestExam>>(
        future: Future.wait(summaries.map((item) =>
            ref.read(staticTestRepositoryProvider).loadExam(item.testNo))),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const PageFrame(
                title: 'Yanlışlarım',
                subtitle: 'Sorular hazırlanıyor.',
                child: Center(child: CircularProgressIndicator()));
          }
          final wrong = snapshot.data!
              .expand((exam) => exam.questions)
              .where((question) =>
                  progress.testQuestionCorrectness[question.id] == false)
              .toList(growable: false);
          return PageFrame(
            title: 'Yanlışlarım',
            subtitle:
                '${wrong.length} yanlış cevap · Canonical soru sırası korunur.',
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
      ),
    );
  }
}

class _WrongQuestion extends ConsumerWidget {
  const _WrongQuestion({required this.question});
  final TestExamQuestion question;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('${question.id} · ${question.question}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            for (final option in question.options) ...<Widget>[
              SizedBox(
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
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('${option.key}. ${option.textEn}',
                          textAlign: TextAlign.left),
                      if (option.textTr != null) ...<Widget>[
                        const SizedBox(height: 3),
                        Text(option.textTr!,
                            textAlign: TextAlign.left,
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 7),
            ],
          ],
        ),
      );
}
