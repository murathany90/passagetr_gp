import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme_tokens.dart';
import '../../core/content_providers.dart';
import '../../core/local_progress.dart';
import '../../models/test_models.dart';
import '../common/page_parts.dart';

class TestModulePage extends ConsumerStatefulWidget {
  const TestModulePage({super.key, required this.moduleNo});
  final int moduleNo;

  @override
  ConsumerState<TestModulePage> createState() => _TestModulePageState();
}

class _TestModulePageState extends ConsumerState<TestModulePage> {
  bool _quickStarted = false;
  int _quickIndex = 0;
  int _quickCorrect = 0;
  String? _selected;
  late List<TestBankWord> _quickWords;
  List<String> _options = const <String>[];
  bool _showTranslations = true;

  @override
  void initState() {
    super.initState();
    ref
        .read(localProgressProvider.notifier)
        .setTestLastModuleNo(widget.moduleNo);
  }

  void _startQuick(List<TestBankWord> words) {
    _quickWords = List<TestBankWord>.of(words)..shuffle(math.Random());
    _quickIndex = 0;
    _quickCorrect = 0;
    _selected = null;
    _options = _quickOptions(_quickWords, 0);
    setState(() => _quickStarted = true);
  }

  List<String> _quickOptions(List<TestBankWord> words, int index) {
    final target = words[index];
    final items = words
        .where((word) => word.id != target.id)
        .map((word) => word.meaningTr)
        .toSet()
        .toList()
      ..shuffle(math.Random());
    return (<String>[target.meaningTr, ...items.take(3)]
      ..shuffle(math.Random()));
  }

  void _answerQuick(String answer) {
    if (_selected != null) return;
    final correct = answer == _quickWords[_quickIndex].meaningTr;
    setState(() {
      _selected = answer;
      if (correct) _quickCorrect++;
    });
  }

  void _nextQuick() {
    if (_quickIndex >= _quickWords.length - 1) return;
    setState(() {
      _quickIndex++;
      _selected = null;
      _options = _quickOptions(_quickWords, _quickIndex);
    });
  }

  Future<void> _confirmReset(TestModuleDetail module) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Modül ${module.moduleNo} ilerlemesi sıfırlansın mı?'),
        content: const Text(
          'Bu modülün bilinen kartları ve eşleştirme tamamlanması silinir. '
          'Favoriler ve diğer modüller korunur.',
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
    ref.read(localProgressProvider.notifier).resetTestModuleProgress(
          moduleNo: module.moduleNo,
          wordIds: module.words.map((word) => word.id),
        );
    setState(() {
      _quickStarted = false;
      _quickIndex = 0;
      _quickCorrect = 0;
      _selected = null;
      _options = const <String>[];
    });
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(testModuleDetailProvider(widget.moduleNo));
    return detail.when(
      loading: () => const PageFrame(
        title: 'Test modülü',
        subtitle: 'Kelimeler hazırlanıyor.',
        child: Center(
            child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator())),
      ),
      error: (error, _) => DataLoadErrorPage(
        message: error.toString(),
        onRetry: () =>
            ref.invalidate(testModuleDetailProvider(widget.moduleNo)),
      ),
      data: (module) {
        return PageFrame(
          title: 'Modül ${module.moduleNo}',
          subtitle:
              '${module.words.length} kelime · Test Bank kaynağı',
          actions: <Widget>[
            OutlinedButton.icon(
              onPressed: () => context.go('/tests'),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Testlere dön'),
            ),
            OutlinedButton.icon(
              onPressed: () => _confirmReset(module),
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('İlerlemeyi sıfırla'),
            ),
          ],
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                  FilledButton.icon(
                    onPressed: () => context
                        .go('/tests/module/${module.moduleNo}/flashcards'),
                    icon: const Icon(Icons.style_rounded),
                    label: const Text('Flash Kart'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () =>
                        context.go('/tests/module/${module.moduleNo}/matching'),
                    icon: const Icon(Icons.compare_arrows_rounded),
                    label: const Text('Eşleştirme'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _startQuick(module.words),
                    icon: const Icon(Icons.bolt_rounded),
                    label: const Text('Hızlı Test'),
                  ),
                ]),
                if (_quickStarted) ...<Widget>[
                  const SizedBox(height: 16),
                  _QuickTest(
                    words: _quickWords,
                    index: _quickIndex,
                    correct: _quickCorrect,
                    options: _options,
                    selected: _selected,
                    onAnswer: _answerQuick,
                    onNext: _nextQuick,
                    onRestart: () => _startQuick(module.words),
                  ),
                ],
                const SizedBox(height: 22),
                Row(children: <Widget>[
                  Expanded(
                    child: Text('Kelimeler',
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => setState(() =>
                        _showTranslations = !_showTranslations),
                    icon: Icon(
                      _showTranslations
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                    ),
                    label: Text(_showTranslations
                        ? 'Çeviriyi gizle'
                        : 'Çeviriyi göster'),
                  ),
                ]),
                const SizedBox(height: 10),
                if (module.words.isEmpty)
                  const SurfaceCard(
                      child: Text('Bu modülde gösterilecek kelime yok.'))
                else
                  LayoutBuilder(builder: (context, constraints) {
                    final twoColumns = constraints.maxWidth >= 720;
                    final width = twoColumns
                        ? (constraints.maxWidth - 12) / 2
                        : constraints.maxWidth;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: module.words
                          .map((word) => SizedBox(
                                width: width,
                                child: _TestWordCard(
                                  word: word,
                                  showTranslations: _showTranslations,
                                ),
                              ))
                          .toList(growable: false),
                    );
                  }),
              ]),
        );
      },
    );
  }
}

class _TestWordCard extends StatefulWidget {
  const _TestWordCard({required this.word, required this.showTranslations});
  final TestBankWord word;
  final bool showTranslations;

  @override
  State<_TestWordCard> createState() => _TestWordCardState();
}

class _TestWordCardState extends State<_TestWordCard> {
  bool _hovering = false;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final word = widget.word;
    final detailsVisible =
        widget.showTranslations || _hovering || _expanded;
    return MouseRegion(
      onEnter: (_) {
        if (!widget.showTranslations) setState(() => _hovering = true);
      },
      onExit: (_) {
        if (_hovering) setState(() => _hovering = false);
      },
      child: SurfaceCard(
        onTap: widget.showTranslations
            ? null
            : () => setState(() => _expanded = !_expanded),
        padding: const EdgeInsets.all(16),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(children: <Widget>[
                Expanded(
                  child: Text(word.headword,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                if (!widget.showTranslations)
                  Icon(_expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded),
              ]),
              if (word.pos.isNotEmpty) ...<Widget>[
                const SizedBox(height: 3),
                Text(word.pos, style: Theme.of(context).textTheme.bodySmall)
              ],
              if (detailsVisible) ...<Widget>[
                const SizedBox(height: 8),
                Text(word.meaningTr,
                    style: Theme.of(context).textTheme.bodyLarge),
                if (word.exampleEn.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(word.exampleEn,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ],
                if (word.exampleTr.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(word.exampleTr,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
                if (word.synonymsRaw != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text('İlişkili: ${word.synonymsRaw}',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ] else ...<Widget>[
                const SizedBox(height: 8),
                Text('Ayrıntı için karta dokunun',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ]),
      ),
    );
  }
}

class _QuickTest extends StatelessWidget {
  const _QuickTest({
    required this.words,
    required this.index,
    required this.correct,
    required this.options,
    required this.selected,
    required this.onAnswer,
    required this.onNext,
    required this.onRestart,
  });
  final List<TestBankWord> words;
  final int index;
  final int correct;
  final List<String> options;
  final String? selected;
  final ValueChanged<String> onAnswer;
  final VoidCallback onNext;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final complete = index >= words.length - 1 && selected != null;
    final target = words[index];
    return SurfaceCard(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
          Text(
              complete
                  ? 'Hızlı test tamamlandı'
                  : '${index + 1} / ${words.length}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          if (complete) ...<Widget>[
            Text('Doğru: $correct / ${words.length}',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            FilledButton.icon(
                onPressed: onRestart,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Yeniden başla')),
          ] else ...<Widget>[
            Text(target.headword,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            for (final option in options) ...<Widget>[
              SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: selected == null ? () => onAnswer(option) : null,
                    style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.all(14)),
                    child: Text(option, textAlign: TextAlign.left),
                  )),
              const SizedBox(height: 8),
            ],
            if (selected != null) ...<Widget>[
              Text(
                  selected == target.meaningTr
                      ? 'Doğru'
                      : 'Doğru cevap: ${target.meaningTr}',
                  style: TextStyle(
                      color: selected == target.meaningTr
                          ? AppThemeTokens.of(context).success
                          : AppThemeTokens.of(context).warning,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              FilledButton(onPressed: onNext, child: const Text('Sonraki')),
            ],
          ],
        ]));
  }
}

class TestFlashcardsPage extends ConsumerStatefulWidget {
  const TestFlashcardsPage({super.key, required this.moduleNo});
  final int moduleNo;

  @override
  ConsumerState<TestFlashcardsPage> createState() => _TestFlashcardsPageState();
}

class _TestFlashcardsPageState extends ConsumerState<TestFlashcardsPage> {
  int _index = 0;
  bool _showBack = false;

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(testModuleDetailProvider(widget.moduleNo));
    return detail.when(
      loading: () => const PageFrame(
          title: 'Flash Kart',
          subtitle: 'Kartlar hazırlanıyor.',
          child: Center(child: CircularProgressIndicator())),
      error: (error, _) => DataLoadErrorPage(message: error.toString()),
      data: (module) {
        final words = module.words;
        if (words.isEmpty) {
          return PageFrame(
            title: 'Modül ${module.moduleNo} · Flash Kart',
            subtitle: 'Gösterilecek kelime yok.',
            actions: <Widget>[
              OutlinedButton.icon(
                  onPressed: () =>
                      context.go('/tests/module/${module.moduleNo}'),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Modüle dön'))
            ],
            child: const SurfaceCard(
                child: Text('Bu modülde gösterilecek kelime yok.')),
          );
        }
        final safeIndex = _index.clamp(0, words.length - 1).toInt();
        final word = words[safeIndex];
        return Focus(
          autofocus: true,
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.space) {
              setState(() => _showBack = !_showBack);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              _move(-1, words.length);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              _know(words);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: PageFrame(
            title: 'Modül ${module.moduleNo} · Flash Kart',
            subtitle:
                '${safeIndex + 1} / ${words.length} · Space: çevir · ← tekrar · → bildim',
            actions: <Widget>[
              OutlinedButton.icon(
                  onPressed: () =>
                      context.go('/tests/module/${module.moduleNo}'),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Modüle dön'))
            ],
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  LinearProgressIndicator(
                      value: (safeIndex + 1) / words.length),
                  const SizedBox(height: 18),
                  SurfaceCard(
                    onTap: () => setState(() => _showBack = !_showBack),
                    padding: const EdgeInsets.all(24),
                    child: SizedBox(
                        width: double.infinity,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(children: <Widget>[
                                Expanded(
                                    child: Text(
                                        _showBack
                                            ? 'Türkçe anlam'
                                            : 'İngilizce kelime',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge)),
                                IconButton(
                                  tooltip: 'Seslendir',
                                  icon: const Icon(Icons.volume_up_outlined),
                                  onPressed: () => ref
                                      .read(
                                          studentTtsControllerProvider.notifier)
                                      .playDictionaryEntry(
                                          entryId: word.id,
                                          text: word.headword),
                                ),
                              ]),
                              const SizedBox(height: 14),
                              Text(_showBack ? word.meaningTr : word.headword,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(fontWeight: FontWeight.w800)),
                              if (!_showBack &&
                                  word.pos.isNotEmpty) ...<Widget>[
                                const SizedBox(height: 5),
                                Text(word.pos,
                                    style:
                                        Theme.of(context).textTheme.bodyMedium)
                              ],
                              if (_showBack &&
                                  word.exampleEn.isNotEmpty) ...<Widget>[
                                const SizedBox(height: 16),
                                Text(word.exampleEn,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.copyWith(fontWeight: FontWeight.w600))
                              ],
                              if (_showBack &&
                                  word.exampleTr.isNotEmpty) ...<Widget>[
                                const SizedBox(height: 4),
                                Text(word.exampleTr,
                                    style:
                                        Theme.of(context).textTheme.bodyMedium)
                              ],
                              if (_showBack &&
                                  word.synonymsRaw != null) ...<Widget>[
                                const SizedBox(height: 12),
                                Text('İlişkili: ${word.synonymsRaw}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall)
                              ],
                            ])),
                  ),
                  const SizedBox(height: 14),
                  Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                    OutlinedButton.icon(
                        onPressed: safeIndex == 0
                            ? null
                            : () => _move(-1, words.length),
                        icon: const Icon(Icons.arrow_back_rounded),
                        label: const Text('Önceki')),
                    OutlinedButton.icon(
                        onPressed: () => _move(1, words.length),
                        icon: const Icon(Icons.replay_rounded),
                        label: const Text('Tekrar')),
                    FilledButton.icon(
                        onPressed: () => _know(words),
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Bildim')),
                  ]),
                ]),
          ),
        );
      },
    );
  }

  void _move(int step, int itemCount) {
    if (itemCount <= 0) return;
    setState(() {
      _index = (_index + step).clamp(0, itemCount - 1).toInt();
      _showBack = false;
    });
  }

  void _know(List<TestBankWord> words) {
    if (words.isEmpty) return;
    final safeIndex = _index.clamp(0, words.length - 1).toInt();
    ref
        .read(localProgressProvider.notifier)
        .markTestFlashcardKnown(words[safeIndex].id);
    _move(1, words.length);
  }
}

class TestMatchingPage extends ConsumerStatefulWidget {
  const TestMatchingPage({super.key, required this.moduleNo});
  final int moduleNo;

  @override
  ConsumerState<TestMatchingPage> createState() => _TestMatchingPageState();
}

class _TestMatchingPageState extends ConsumerState<TestMatchingPage> {
  List<TestBankWord> _deck = const <TestBankWord>[];
  int _round = 0;
  int _correct = 0;
  int _wrong = 0;
  String? _selectedId;
  Set<String> _resolved = <String>{};
  int? _completionSavedFor;

  void _prepare(List<TestBankWord> words) {
    if (_deck.isNotEmpty) return;
    _deck = List<TestBankWord>.of(words)..shuffle(math.Random());
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(testModuleDetailProvider(widget.moduleNo));
    return detail.when(
      loading: () => const PageFrame(
          title: 'Eşleştirme',
          subtitle: 'Tur hazırlanıyor.',
          child: Center(child: CircularProgressIndicator())),
      error: (error, _) => DataLoadErrorPage(message: error.toString()),
      data: (module) {
        _prepare(module.words);
        final roundCount = (_deck.length / 5).ceil();
        if (_round >= roundCount) return _complete(context, module, roundCount);
        final items = _deck.skip(_round * 5).take(5).toList(growable: false);
        final selected = _selectedId == null
            ? null
            : items.where((word) => word.id == _selectedId).firstOrNull;
        final meanings = List<TestBankWord>.of(items)
          ..shuffle(math.Random(_round + 31));
        return PageFrame(
          title: 'Modül ${module.moduleNo} · Eşleştirme',
          subtitle:
              'Tur ${_round + 1} / $roundCount · Doğru: $_correct · Yanlış: $_wrong',
          actions: <Widget>[
            OutlinedButton.icon(
                onPressed: () => context.go('/tests/module/${module.moduleNo}'),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Modüle dön'))
          ],
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                LinearProgressIndicator(
                    value: (_round * 5 + _resolved.length) / _deck.length),
                const SizedBox(height: 16),
                LayoutBuilder(builder: (context, constraints) {
                  final desktop = constraints.maxWidth >= 600;
                  final wordList = _wordButtons(items);
                  final meaningList = _meaningButtons(items, meanings);
                  if (desktop) {
                    return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(child: wordList),
                          const SizedBox(width: 14),
                          Expanded(child: meaningList),
                        ]);
                  }
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        if (selected == null) ...<Widget>[
                          Text('İngilizce kelimeyi seç',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          wordList
                        ] else ...<Widget>[
                          Text(selected.headword,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 12),
                          Text('Türkçe anlamı seç',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          meaningList
                        ],
                      ]);
                }),
              ]),
        );
      },
    );
  }

  Widget _wordButtons(List<TestBankWord> items) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: items
            .where((word) => !_resolved.contains(word.id))
            .map((word) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton(
                    onPressed: () => setState(() => _selectedId = word.id),
                    style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.all(14)),
                    child: Text(word.headword, textAlign: TextAlign.left),
                  ),
                ))
            .toList(growable: false),
      );

  Widget _meaningButtons(
          List<TestBankWord> items, List<TestBankWord> meanings) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: meanings
            .where((word) => !_resolved.contains(word.id))
            .map((word) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton(
                    onPressed:
                        _selectedId == null ? null : () => _match(items, word),
                    style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.all(14)),
                    child: Text(word.meaningTr, textAlign: TextAlign.left),
                  ),
                ))
            .toList(growable: false),
      );

  void _match(List<TestBankWord> items, TestBankWord meaning) {
    final selected = items.where((word) => word.id == _selectedId).firstOrNull;
    if (selected == null) return;
    final correct = selected.id == meaning.id;
    setState(() {
      if (correct) {
        _resolved.add(selected.id);
        _correct++;
      } else {
        _wrong++;
      }
      _selectedId = null;
      if (_resolved.length == items.length) {
        _round++;
        _resolved = <String>{};
      }
    });
  }

  Widget _complete(BuildContext context, TestModuleDetail module, int rounds) {
    if (_completionSavedFor != module.moduleNo) {
      _completionSavedFor = module.moduleNo;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(localProgressProvider.notifier)
            .markTestMatchingCompleted(module.moduleNo);
      });
    }
    final total = _correct + _wrong;
    final rate = total == 0 ? 0 : (_correct * 100 / total).round();
    return PageFrame(
      title: 'Eşleştirme tamamlandı',
      subtitle: '${module.moduleNo}. modül · $rounds tur',
      child: SurfaceCard(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
            Text('Doğru: $_correct · Yanlış: $_wrong · Başarı: %$rate',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
              FilledButton.icon(
                  onPressed: () => setState(() {
                        _deck = const [];
                        _round = 0;
                        _correct = 0;
                        _wrong = 0;
                        _resolved = <String>{};
                        _completionSavedFor = null;
                      }),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Yeniden başla')),
              OutlinedButton(
                  onPressed: () =>
                      context.go('/tests/module/${module.moduleNo}'),
                  child: const Text('Modüle dön')),
            ]),
          ])),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
