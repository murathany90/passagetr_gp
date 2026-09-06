import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/content_providers.dart';
import '../../models/test_models.dart';
import '../common/page_parts.dart';

class TestStructuresPage extends ConsumerStatefulWidget {
  const TestStructuresPage({super.key});

  @override
  ConsumerState<TestStructuresPage> createState() => _TestStructuresPageState();
}

class _TestStructuresPageState extends ConsumerState<TestStructuresPage> {
  String? _category;
  _StructureMode _mode = _StructureMode.list;
  int _index = 0;
  bool _showMeaning = false;
  List<TestStructure> _deck = const <TestStructure>[];
  String? _deckScope;

  @override
  Widget build(BuildContext context) {
    final bank = ref.watch(testStructuresProvider);
    return bank.when(
      loading: () => const PageFrame(
          title: 'Yapılar',
          subtitle: 'Canonical yapılar hazırlanıyor.',
          child: Center(child: CircularProgressIndicator())),
      error: (error, _) => DataLoadErrorPage(
          message: error.toString(),
          onRetry: () => ref.invalidate(testStructuresProvider)),
      data: (data) {
        final validCategory =
            data.categories.contains(_category) ? _category : null;
        final items = data.structures
            .where((item) =>
                validCategory == null || item.category == validCategory)
            .toList(growable: false);
        _ensureDeck(items, validCategory);
        return PageFrame(
          title: 'Yapılar',
          subtitle:
              '${items.length} canonical yapı · Kaynakta olmayan örnek gösterilmez.',
          actions: <Widget>[
            OutlinedButton.icon(
                onPressed: () => context.go('/tests'),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Testlere dön'))
          ],
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SurfaceCard(
                  padding: const EdgeInsets.all(14),
                  child: LayoutBuilder(
                      builder: (context, constraints) =>
                          Wrap(spacing: 10, runSpacing: 10, children: <Widget>[
                            SizedBox(
                              width: constraints.maxWidth >= 520
                                  ? 280
                                  : constraints.maxWidth,
                              child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: validCategory,
                                decoration: const InputDecoration(
                                    labelText: 'Kategori', isDense: true),
                                items: <DropdownMenuItem<String>>[
                                  const DropdownMenuItem(
                                      value: null, child: Text('Tümü')),
                                  ...data.categories.map((category) =>
                                      DropdownMenuItem(
                                          value: category,
                                          child: Text(category,
                                              overflow:
                                                  TextOverflow.ellipsis))),
                                ],
                                onChanged: (value) => setState(() {
                                  _category = value;
                                  _index = 0;
                                  _showMeaning = false;
                                  _deck = const [];
                                }),
                              ),
                            ),
                            SegmentedButton<_StructureMode>(
                              segments: const <ButtonSegment<_StructureMode>>[
                                ButtonSegment(
                                    value: _StructureMode.list,
                                    label: Text('Liste'),
                                    icon: Icon(Icons.list_alt_rounded)),
                                ButtonSegment(
                                    value: _StructureMode.flashcards,
                                    label: Text('Kart'),
                                    icon: Icon(Icons.style_rounded)),
                                ButtonSegment(
                                    value: _StructureMode.matching,
                                    label: Text('Eşleştirme'),
                                    icon: Icon(Icons.compare_arrows_rounded)),
                              ],
                              selected: <_StructureMode>{_mode},
                              showSelectedIcon: false,
                              onSelectionChanged: (value) => setState(() {
                                _mode = value.first;
                                _index = 0;
                                _showMeaning = false;
                              }),
                            ),
                          ])),
                ),
                const SizedBox(height: 16),
                if (items.isEmpty)
                  const SurfaceCard(
                      child: Text('Bu kategoride canonical yapı bulunmuyor.'))
                else
                  switch (_mode) {
                    _StructureMode.list => _StructureList(items: items),
                    _StructureMode.flashcards => _StructureFlashcard(
                        items: _deck,
                        index: _index,
                        showMeaning: _showMeaning,
                        onFlip: () =>
                            setState(() => _showMeaning = !_showMeaning),
                        onMove: (offset) => setState(() {
                          _index = (_index + offset)
                              .clamp(0, _deck.length - 1)
                              .toInt();
                          _showMeaning = false;
                        }),
                      ),
                    _StructureMode.matching => _StructureMatching(
                        items: _deck.take(10).toList(growable: false)),
                  },
              ]),
        );
      },
    );
  }

  void _ensureDeck(List<TestStructure> items, String? category) {
    final scope = category ?? '__all__';
    if (_deckScope == scope && _deck.length == items.length) {
      return;
    }
    _deck = List<TestStructure>.of(items)..shuffle(math.Random());
    _deckScope = scope;
    _index = 0;
  }
}

enum _StructureMode { list, flashcards, matching }

class _StructureList extends StatelessWidget {
  const _StructureList({required this.items});
  final List<TestStructure> items;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 720;
        final width =
            twoColumns ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
        return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: items
                .map((item) =>
                    SizedBox(width: width, child: _StructureCard(item: item)))
                .toList(growable: false));
      });
}

class _StructureCard extends StatelessWidget {
  const _StructureCard({required this.item});
  final TestStructure item;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        padding: const EdgeInsets.all(16),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(item.category,
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              Text(item.structure,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(item.meaningTr,
                  style: Theme.of(context).textTheme.bodyMedium),
              if (item.exampleEn != null) ...<Widget>[
                const SizedBox(height: 10),
                Text(item.exampleEn!,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600))
              ],
              if (item.exampleTr != null) ...<Widget>[
                const SizedBox(height: 3),
                Text(item.exampleTr!,
                    style: Theme.of(context).textTheme.bodySmall)
              ],
            ]),
      );
}

class _StructureFlashcard extends StatelessWidget {
  const _StructureFlashcard(
      {required this.items,
      required this.index,
      required this.showMeaning,
      required this.onFlip,
      required this.onMove});
  final List<TestStructure> items;
  final int index;
  final bool showMeaning;
  final VoidCallback onFlip;
  final ValueChanged<int> onMove;

  @override
  Widget build(BuildContext context) {
    final item = items[index];
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('${index + 1} / ${items.length}',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          SurfaceCard(
              onTap: onFlip,
              child: SizedBox(
                  width: double.infinity,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(showMeaning ? item.meaningTr : item.structure,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        if (showMeaning && item.exampleEn != null) ...<Widget>[
                          const SizedBox(height: 14),
                          Text(item.exampleEn!,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(fontWeight: FontWeight.w600))
                        ],
                        if (showMeaning && item.exampleTr != null) ...<Widget>[
                          const SizedBox(height: 3),
                          Text(item.exampleTr!,
                              style: Theme.of(context).textTheme.bodyMedium)
                        ],
                      ]))),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: <Widget>[
            OutlinedButton(
                onPressed: index == 0 ? null : () => onMove(-1),
                child: const Text('Önceki')),
            OutlinedButton(
                onPressed: onFlip,
                child: Text(showMeaning ? 'Gizle' : 'Anlamı göster')),
            FilledButton(
                onPressed: index == items.length - 1 ? null : () => onMove(1),
                child: const Text('Sonraki')),
          ]),
        ]);
  }
}

class _StructureMatching extends StatefulWidget {
  const _StructureMatching({required this.items});
  final List<TestStructure> items;

  @override
  State<_StructureMatching> createState() => _StructureMatchingState();
}

class _StructureMatchingState extends State<_StructureMatching> {
  String? selected;
  final Set<String> resolved = <String>{};
  int correct = 0;
  int wrong = 0;

  @override
  Widget build(BuildContext context) {
    final meanings = List<TestStructure>.of(widget.items)
      ..shuffle(math.Random(7));
    final done = resolved.length == widget.items.length;
    return SurfaceCard(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
          Text(
              done
                  ? 'Tur tamamlandı · Doğru: $correct · Yanlış: $wrong'
                  : 'Bir yapı seçin, sonra karşılığını işaretleyin.',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (!done)
            LayoutBuilder(builder: (context, constraints) {
              final desktop = constraints.maxWidth >= 640;
              final left = _structureButtons(widget.items, true);
              final right = _structureButtons(meanings, false);
              return desktop
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                          Expanded(child: left),
                          const SizedBox(width: 12),
                          Expanded(child: right)
                        ])
                  : Column(children: <Widget>[
                      left,
                      const SizedBox(height: 8),
                      right
                    ]);
            }),
          if (done) ...<Widget>[
            const SizedBox(height: 12),
            FilledButton.icon(
                onPressed: () => setState(() {
                      selected = null;
                      resolved.clear();
                      correct = 0;
                      wrong = 0;
                    }),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Yeniden başla'))
          ],
        ]));
  }

  Widget _structureButtons(List<TestStructure> items, bool isStructure) =>
      Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: items
              .where((item) => !resolved.contains(item.id))
              .map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton(
                      onPressed: isStructure
                          ? () => setState(() => selected = item.id)
                          : selected == null
                              ? null
                              : () => _choose(item),
                      style: OutlinedButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.all(13)),
                      child: Text(isStructure ? item.structure : item.meaningTr,
                          textAlign: TextAlign.left),
                    ),
                  ))
              .toList(growable: false));

  void _choose(TestStructure answer) => setState(() {
        if (answer.id == selected) {
          resolved.add(answer.id);
          correct++;
        } else {
          wrong++;
        }
        selected = null;
      });
}
