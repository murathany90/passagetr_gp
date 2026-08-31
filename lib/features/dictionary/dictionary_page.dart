import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme_tokens.dart';
import '../../core/content_providers.dart';
import '../../models/content_models.dart';
import '../../repositories/static_dictionary_repository.dart';
import '../common/page_parts.dart';
import '../tts/student_tts_icon_button.dart';
import '../words/dictionary_detail_sheet.dart';

class DictionaryPage extends ConsumerStatefulWidget {
  const DictionaryPage({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  ConsumerState<DictionaryPage> createState() => _DictionaryPageState();
}

class _DictionaryPageState extends ConsumerState<DictionaryPage> {
  late final TextEditingController _controller;
  var _result = const _DictionarySearchResult.empty();
  var _randomEntries = const <DictionaryEntry>[];
  var _isLoading = false;
  var _isLoadingRandom = false;
  DictionaryMetadata? _metadata;
  Object? _error;
  Object? _randomError;
  var _request = 0;
  var _randomRequest = 0;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery ?? '');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMetadata();
      if (normalizeDictionaryLookup(_controller.text).isEmpty) {
        _loadRandomEntries();
      } else {
        _search(_controller.text);
      }
    });
  }

  Future<void> _loadMetadata() async {
    try {
      final metadata =
          await ref.read(staticDictionaryRepositoryProvider).metadata();
      if (mounted) setState(() => _metadata = metadata);
    } catch (_) {
      // Search and lazy shard errors are surfaced by their own UI states.
    }
  }

  @override
  void didUpdateWidget(covariant DictionaryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialQuery != oldWidget.initialQuery &&
        widget.initialQuery != _controller.text) {
      _controller.text = widget.initialQuery ?? '';
      _search(_controller.text);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadRandomEntries() async {
    final request = ++_randomRequest;
    setState(() {
      _isLoadingRandom = true;
      _randomError = null;
    });
    try {
      final entries =
          await ref.read(staticDictionaryRepositoryProvider).randomEntries(
                count: 20,
                exclude: _randomEntries.map((entry) => entry.normalizedKey),
              );
      if (!mounted || request != _randomRequest) return;
      setState(() {
        _randomEntries = entries;
        _isLoadingRandom = false;
      });
    } catch (error) {
      if (!mounted || request != _randomRequest) return;
      setState(() {
        _randomError = error;
        _isLoadingRandom = false;
      });
    }
  }

  Future<void> _openRandomEntry(DictionaryEntry entry) async {
    try {
      final entries = await ref
          .read(staticDictionaryRepositoryProvider)
          .findAll(entry.enWord);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => DictionaryDetailSheet(
          entries: entries.isEmpty ? <DictionaryEntry>[entry] : entries,
          showOpenInDictionaryAction: false,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _randomError = error);
    }
  }

  Future<void> _search(String value) async {
    final query = normalizeDictionaryLookup(value);
    final request = ++_request;
    if (query.isEmpty) {
      setState(() {
        _result = const _DictionarySearchResult.empty();
        _isLoading = false;
        _error = null;
      });
      if (_randomEntries.isEmpty && !_isLoadingRandom) {
        await _loadRandomEntries();
      }
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final repository = ref.read(staticDictionaryRepositoryProvider);
      final values = await Future.wait<
          List<DictionaryEntry>>(<Future<List<DictionaryEntry>>>[
        repository.findAll(query),
        repository.suggest(query),
      ]);
      if (!mounted || request != _request) return;
      final exact = values[0];
      final exactKeys = exact.map((entry) => entry.normalizedKey).toSet();
      setState(() {
        _result = _DictionarySearchResult(
          query: query,
          exact: exact,
          suggestions: values[1]
              .where((entry) => !exactKeys.contains(entry.normalizedKey))
              .toList(growable: false),
        );
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'Sözlük',
        subtitle: _metadata == null
            ? 'Tam eşleşme ve yalnız gerekli lazy shard yüklemesi.'
            : '${_formatCount(_metadata!.recordCount)} kayıt · '
                '${_formatCount(_metadata!.uniqueHeadwords)} başlık · '
                'lazy yükleme',
        maxWidth: 760,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _controller,
              autofocus: widget.initialQuery?.isNotEmpty ?? false,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: 'İngilizce kelime ara...',
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Aramayı temizle',
                        onPressed: () {
                          _controller.clear();
                          _search('');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
              onChanged: _search,
              onSubmitted: _search,
            ),
            const SizedBox(height: 14),
            if (_controller.text.trim().isEmpty)
              _RandomDictionarySection(
                entries: _randomEntries,
                isLoading: _isLoadingRandom,
                error: _randomError,
                onRefresh: _loadRandomEntries,
                onEntryTap: _openRandomEntry,
              )
            else if (_isLoading)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator()))
            else if (_error != null)
              _DictionaryHint(
                icon: Icons.error_outline_rounded,
                text: 'DATA_LOAD_ERROR: ${_error.toString()}',
              )
            else
              _DictionaryResults(
                result: _result,
                onSuggestion: (entry) {
                  _controller.text = entry.enWord;
                  _controller.selection =
                      TextSelection.collapsed(offset: _controller.text.length);
                  _search(entry.enWord);
                },
              ),
          ],
        ),
      );
}

class _RandomDictionarySection extends StatelessWidget {
  const _RandomDictionarySection({
    required this.entries,
    required this.isLoading,
    required this.error,
    required this.onRefresh,
    required this.onEntryTap,
  });

  final List<DictionaryEntry> entries;
  final bool isLoading;
  final Object? error;
  final VoidCallback onRefresh;
  final ValueChanged<DictionaryEntry> onEntryTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(children: <Widget>[
              Expanded(
                child: Text('Rastgele 20 Kelime',
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              OutlinedButton.icon(
                onPressed: isLoading ? null : onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('20 Yeni Kelime'),
              ),
            ]),
            const SizedBox(height: 10),
            if (isLoading && entries.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (error != null)
              _DictionaryHint(
                icon: Icons.error_outline_rounded,
                text: 'DATA_LOAD_ERROR: ${error.toString()}',
              )
            else if (entries.isNotEmpty)
              _RandomDictionaryList(entries: entries, onEntryTap: onEntryTap),
          ],
        ),
      );
}

class _RandomDictionaryList extends ConsumerWidget {
  const _RandomDictionaryList({
    required this.entries,
    required this.onEntryTap,
  });

  final List<DictionaryEntry> entries;
  final ValueChanged<DictionaryEntry> onEntryTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tts = ref.watch(studentTtsControllerProvider);
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          for (var index = 0; index < entries.length; index++) ...<Widget>[
            _RandomDictionaryTile(
              entry: entries[index],
              isSpeaking:
                  tts.isSpeaking && tts.activeWordId == entries[index].id,
              isInitializing:
                  tts.isInitializing && tts.activeWordId == entries[index].id,
              isUnavailable: tts.isUnavailable,
              onPlay: () => ref
                  .read(studentTtsControllerProvider.notifier)
                  .playDictionaryEntry(
                    entryId: entries[index].id,
                    text: entries[index].enWord,
                  ),
              onStop: () =>
                  ref.read(studentTtsControllerProvider.notifier).stop(),
              onTap: () => onEntryTap(entries[index]),
            ),
            if (index != entries.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _RandomDictionaryTile extends StatelessWidget {
  const _RandomDictionaryTile({
    required this.entry,
    required this.isSpeaking,
    required this.isInitializing,
    required this.isUnavailable,
    required this.onPlay,
    required this.onStop,
    required this.onTap,
  });

  final DictionaryEntry entry;
  final bool isSpeaking;
  final bool isInitializing;
  final bool isUnavailable;
  final Future<void> Function() onPlay;
  final Future<void> Function() onStop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(entry.enWord,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 3),
                      Text(
                        entry.pos == null || entry.pos!.isEmpty
                            ? entry.trMeaning
                            : '${entry.trMeaning} · ${entry.pos}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                StudentTtsIconButton(
                  tooltip: 'İngilizce dinle',
                  isSpeaking: isSpeaking,
                  isInitializing: isInitializing,
                  isUnavailable: isUnavailable,
                  visualDensity: VisualDensity.compact,
                  onPlay: onPlay,
                  onStop: onStop,
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      );
}

class _DictionaryResults extends StatelessWidget {
  const _DictionaryResults({required this.result, required this.onSuggestion});

  final _DictionarySearchResult result;
  final ValueChanged<DictionaryEntry> onSuggestion;

  @override
  Widget build(BuildContext context) {
    if (!result.hasResults) {
      return const _DictionaryHint(
        icon: Icons.search_off_rounded,
        text: 'Bu kelime için yerel sözlükte sonuç bulunamadı.',
      );
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (result.exact.isNotEmpty) ...<Widget>[
            Text('Tam eşleşme', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 9),
            _DictionaryResultCard(entries: result.exact),
          ],
          if (result.suggestions.isNotEmpty) ...<Widget>[
            const SizedBox(height: 18),
            Text('Başlayan kelimeler',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                children: result.suggestions
                    .map((entry) => ListTile(
                          dense: true,
                          title: Text(entry.enWord),
                          subtitle: entry.pos == null ? null : Text(entry.pos!),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => onSuggestion(entry),
                        ))
                    .toList(growable: false),
              ),
            ),
          ],
        ]);
  }
}

class _DictionaryResultCard extends ConsumerWidget {
  const _DictionaryResultCard({required this.entries});

  final List<DictionaryEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final first = entries.first;
    final tokens = AppThemeTokens.of(context);
    final tts = ref.watch(studentTtsControllerProvider);
    final speaking = tts.isSpeaking && tts.activeWordId == first.id;
    return SurfaceCard(
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Text(first.enWord,
                        style: Theme.of(context).textTheme.headlineSmall),
                  ),
                  StudentTtsIconButton(
                    iconSize: 24,
                    isSpeaking: speaking,
                    isInitializing:
                        tts.isInitializing && tts.activeWordId == first.id,
                    isUnavailable: tts.isUnavailable,
                    onPlay: () => ref
                        .read(studentTtsControllerProvider.notifier)
                        .playDictionaryEntry(
                            entryId: first.id, text: first.enWord),
                    onStop: () =>
                        ref.read(studentTtsControllerProvider.notifier).stop(),
                  ),
                ]),
            const SizedBox(height: 12),
            for (var index = 0; index < entries.length; index++)
              Padding(
                padding: EdgeInsets.only(
                    bottom: index == entries.length - 1 ? 0 : 11),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('${index + 1}.',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              if (entries[index].pos case final pos?)
                                Text(pos,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: tokens.hero,
                                          fontWeight: FontWeight.w800,
                                        )),
                              Text(entries[index].trMeaning,
                                  style: Theme.of(context).textTheme.bodyLarge),
                            ]),
                      ),
                    ]),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => DictionaryDetailSheet(
                    entries: entries,
                    showOpenInDictionaryAction: false,
                  ),
                ),
                child: const Text('Ayrıntılar'),
              ),
            ),
          ]),
    );
  }
}

class _DictionaryHint extends StatelessWidget {
  const _DictionaryHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        child: Row(children: <Widget>[
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ]),
      );
}

class _DictionarySearchResult {
  const _DictionarySearchResult({
    required this.query,
    required this.exact,
    required this.suggestions,
  });

  const _DictionarySearchResult.empty()
      : query = '',
        exact = const <DictionaryEntry>[],
        suggestions = const <DictionaryEntry>[];

  final String query;
  final List<DictionaryEntry> exact;
  final List<DictionaryEntry> suggestions;
  bool get hasResults => exact.isNotEmpty || suggestions.isNotEmpty;
}

String _formatCount(int value) {
  final digits = value.toString();
  return digits.replaceAllMapped(
    RegExp(r'(?<!^)(?=(\d{3})+$)'),
    (_) => '.',
  );
}
