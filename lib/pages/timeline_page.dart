import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../channels.dart';
import '../format.dart';
import '../markdown_export.dart';
import '../widgets/copyable_text.dart';
import '../widgets/workflow.dart';
import 'search_page.dart';
import 'settings_page.dart';

class TimelinePage extends StatefulWidget {
  const TimelinePage({super.key});

  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  List<Map<Object?, Object?>> items = const [];
  String? error;
  int _refreshRequest = 0;
  final _scrollController = ScrollController();
  bool _selecting = false;
  bool _deleting = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    workflowActivity.addListener(refresh);
    refresh();
  }

  @override
  void dispose() {
    workflowActivity.removeListener(refresh);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    final request = ++_refreshRequest;
    try {
      final values = await nativeCommands.invokeListMethod<Object?>('timeline');
      if (!mounted || request != _refreshRequest) return;
      setState(() {
        items = (values ?? const [])
            .map((value) => Map<Object?, Object?>.from(value! as Map))
            .toList();
        error = null;
        // Keep selection consistent with what still exists after refresh.
        if (_selecting) {
          final liveIds = items.map((item) => item['id']).toSet();
          _selectedIds.removeWhere((id) => !liveIds.contains(id));
          if (_selectedIds.isEmpty) _selecting = false;
        }
      });
    } on PlatformException catch (exception) {
      if (mounted && request == _refreshRequest) {
        setState(() => error = exception.message);
      }
    }
  }

  Future<void> run(String command) async {
    try {
      await workflowActivity.run(command);
      await refresh();
    } on PlatformException catch (exception) {
      if (mounted) setState(() => error = exception.message);
    }
  }

  Future<void> retry(String command, String id) async {
    try {
      await nativeCommands.invokeMethod(command, {'id': id});
      await workflowActivity.refresh();
      await refresh();
    } on PlatformException catch (exception) {
      if (mounted) setState(() => error = exception.message);
    }
  }

  Future<void> retryAll(String command) async {
    try {
      await nativeCommands.invokeMethod<int>(command);
      await workflowActivity.refresh();
      await refresh();
    } on PlatformException catch (exception) {
      if (mounted) setState(() => error = exception.message);
    }
  }

  Future<void> stop(String command) async {
    try {
      await workflowActivity.stop(command);
      await refresh();
    } on PlatformException catch (exception) {
      if (mounted) setState(() => error = exception.message);
    }
  }

  Future<void> deleteTranscript(Map<Object?, Object?> item) async {
    final id = item['id'];
    if (id is! String || id.isEmpty) {
      if (mounted) {
        setState(
          () => error =
              'This transcript is missing its id and cannot be deleted.',
        );
      }
      return;
    }
    try {
      await nativeCommands.invokeMethod(
        item['isEpisode'] == true ? 'deleteEpisode' : 'deleteSegment',
        {'id': id},
      );
      await refresh();
    } on PlatformException catch (exception) {
      // Reconcile in case the recording was already deleted natively.
      await refresh();
      if (mounted) {
        setState(
          () => error = exception.message ?? 'Could not delete this session.',
        );
      }
    }
  }

  Iterable<Map<Object?, Object?>> get _selectedItems =>
      items.where((item) => _selectedIds.contains(item['id']));

  void _toggleSelect(String id) => setState(() {
    if (!_selectedIds.remove(id)) _selectedIds.add(id);
  });

  void _enterSelection(String id) => setState(() {
    _selecting = true;
    _selectedIds
      ..clear()
      ..add(id);
  });

  void _exitSelection() => setState(() {
    _selecting = false;
    _selectedIds.clear();
  });

  void _toggleSelectAll() => setState(() {
    final allSelected = items.isNotEmpty && _selectedIds.length == items.length;
    _selectedIds
      ..clear()
      ..addAll(
        allSelected
            ? const <String>[]
            : items.map((item) => item['id']! as String),
      );
  });

  Future<void> _deleteSelected() async {
    final selected = _selectedItems.toList();
    if (selected.isEmpty || _deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'Delete ${selected.length} session'
          '${selected.length == 1 ? '' : 's'}?',
        ),
        content: const Text(
          'This removes the local encrypted recordings and their transcripts. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      final failures = <String, String>{};
      for (final item in selected) {
        final id = item['id'];
        if (id is! String || id.isEmpty) {
          failures['$id'] = 'Missing id.';
          continue;
        }
        try {
          await nativeCommands.invokeMethod(
            item['isEpisode'] == true ? 'deleteEpisode' : 'deleteSegment',
            {'id': id},
          );
        } on PlatformException catch (exception) {
          failures[id] = exception.message ?? 'Could not delete this session.';
        } on Object catch (exception) {
          failures[id] = exception.toString();
        }
        if (!mounted) return;
      }
      await refresh();
      if (!mounted) return;
      setState(() {
        if (failures.isEmpty) {
          _selecting = false;
          _selectedIds.clear();
        } else {
          // Keep the failed sessions selected so the user can retry or exit.
          _selectedIds.removeWhere((id) => !failures.containsKey(id));
          if (_selectedIds.isEmpty) _selecting = false;
        }
      });
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            failures.isEmpty
                ? 'Deleted ${selected.length} session'
                      '${selected.length == 1 ? '' : 's'}'
                : 'Deleted ${selected.length - failures.length} of '
                      '${selected.length} sessions',
          ),
        ),
      );
      if (failures.isNotEmpty) {
        setState(() => error = failures.values.join('\n'));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _exportSelected() async {
    final selected = _selectedItems.toList();
    if (selected.isEmpty) return;
    try {
      await nativeCommands.invokeMethod('exportDocument', {
        'content': buildSessionsMarkdown(selected),
        'fileName': buildSessionsFileName(selected),
        'mimeType': 'text/markdown',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Markdown export saved')));
    } on PlatformException catch (exception) {
      if (exception.code == 'export_cancelled') return;
      if (mounted) setState(() => error = exception.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allSelected = items.isNotEmpty && _selectedIds.length == items.length;
    return Scaffold(
      appBar: AppBar(
        leading: _selecting
            ? IconButton(
                tooltip: 'Exit selection',
                onPressed: _exitSelection,
                icon: const Icon(Icons.close),
              )
            : null,
        automaticallyImplyLeading: !_selecting,
        title: Text(
          _selecting ? '${_selectedIds.length} selected' : 'Transcripts',
        ),
        actions: [
          if (_selecting)
            IconButton(
              tooltip: allSelected ? 'Deselect all' : 'Select all',
              onPressed: items.isEmpty ? null : _toggleSelectAll,
              icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
            )
          else ...[
            IconButton(
              tooltip: 'Search recall',
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SearchPage())),
              icon: const Icon(Icons.search),
            ),
            IconButton(
              tooltip: 'Settings',
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
              icon: const Icon(Icons.settings),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ],
      ),
      bottomNavigationBar: _selecting
          ? BottomAppBar(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Tooltip(
                      message: 'Export selection as markdown',
                      child: OutlinedButton.icon(
                        onPressed: _selectedIds.isEmpty
                            ? null
                            : _exportSelected,
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Export .md'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Tooltip(
                      message: 'Delete selected sessions',
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onError,
                        ),
                        onPressed: _selectedIds.isEmpty || _deleting
                            ? null
                            : _deleteSelected,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete'),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: refresh,
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          interactive: true,
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.all(20),
            children: [
              ValueListenableBuilder(
                valueListenable: workflowActivity,
                builder: (context, activity, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    WorkflowBanner(activity: activity),
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.playlist_play,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Queue processing',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Tooltip(
                                        message: activity.transcribing
                                            ? 'Stop transcription'
                                            : 'Transcribe pending',
                                        child: FilledButton.icon(
                                          onPressed: () => activity.transcribing
                                              ? stop('stopTranscription')
                                              : run('transcribeNow'),
                                          icon: Icon(
                                            activity.transcribing
                                                ? Icons.stop
                                                : Icons.graphic_eq,
                                          ),
                                          label: Text(
                                            activity.transcribing
                                                ? 'Stop transcript'
                                                : 'Transcribe',
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Tooltip(
                                        message: 'Retry failed transcripts',
                                        child: OutlinedButton.icon(
                                          onPressed: () => retryAll(
                                            'retryFailedTranscriptions',
                                          ),
                                          icon: const Icon(
                                            Icons.refresh,
                                            size: 18,
                                          ),
                                          label: const Text('Retry'),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Tooltip(
                                        message: activity.summarizing
                                            ? 'Stop summary'
                                            : 'Summarize pending',
                                        child: FilledButton.tonalIcon(
                                          onPressed: () => activity.summarizing
                                              ? stop('stopSummary')
                                              : run('summarizeNow'),
                                          icon: Icon(
                                            activity.summarizing
                                                ? Icons.stop
                                                : Icons.summarize_outlined,
                                          ),
                                          label: Text(
                                            activity.summarizing
                                                ? 'Stop summary'
                                                : 'Summarize',
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Tooltip(
                                        message: 'Retry failed summaries',
                                        child: OutlinedButton.icon(
                                          onPressed: () =>
                                              retryAll('retryFailedSummaries'),
                                          icon: const Icon(
                                            Icons.refresh,
                                            size: 18,
                                          ),
                                          label: const Text('Retry'),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No transcripts or summaries yet.'),
                  ),
                ),
              for (var index = 0; index < items.length; index++)
                _TimelineEntry(
                  last: index == items.length - 1,
                  child: _TranscriptSummaryCard(
                    item: items[index],
                    time: formatTimestamp,
                    retryTranscription: (id) => retry('retryTranscription', id),
                    retrySummary: () =>
                        retry('retrySummary', items[index]['id']! as String),
                    onDelete: () => deleteTranscript(items[index]),
                    selecting: _selecting,
                    selected: _selectedIds.contains(items[index]['id']),
                    onToggleSelect: () =>
                        _toggleSelect(items[index]['id']! as String),
                    onLongPress: () =>
                        _enterSelection(items[index]['id']! as String),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({required this.child, required this.last});
  final Widget child;
  final bool last;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned(
        left: 8,
        top: 18,
        bottom: last ? null : 0,
        height: last ? 2 : null,
        child: Container(
          width: 2,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(top: 18),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).scaffoldBackgroundColor,
                width: 4,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: child,
            ),
          ),
        ],
      ),
    ],
  );
}

class _TranscriptSummaryCard extends StatelessWidget {
  const _TranscriptSummaryCard({
    required this.item,
    required this.time,
    required this.retryTranscription,
    required this.retrySummary,
    required this.onDelete,
    required this.selecting,
    required this.selected,
    required this.onToggleSelect,
    required this.onLongPress,
  });

  final Map<Object?, Object?> item;
  final String Function(int) time;
  final ValueChanged<String> retryTranscription;
  final VoidCallback retrySummary;
  final VoidCallback onDelete;
  final bool selecting;
  final bool selected;
  final VoidCallback onToggleSelect;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final summary = _summaryMap(item['summary'] as String?);
    final title =
        _string(summary?['local_title']) ??
        _string(summary?['title']) ??
        'Recording summary';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: onLongPress,
      onTap: selecting ? onToggleSelect : null,
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: selected
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (selecting)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Checkbox(
                        value: selected,
                        onChanged: (_) => onToggleSelect(),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.auto_awesome_outlined),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          time(item['startedAt']! as int),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        _StateChip(
                          label: item['summaryState'] as String? ?? 'WAITING',
                        ),
                      ],
                    ),
                  ),
                  if (!selecting)
                    IconButton(
                      tooltip: 'Delete transcript',
                      onPressed: () => _confirmDelete(context),
                      icon: const Icon(Icons.delete_outline),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _SummaryContent(
                value: item['summary'] as String?,
                parsed: summary,
              ),
              if (item['summaryError'] case final String message)
                _ErrorText(message: message),
              if (_retryable(item['summaryState']))
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: retrySummary,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Resubmit summary'),
                  ),
                ),
              const Divider(height: 28),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                leading: const Icon(Icons.format_quote),
                title: const Text('Transcript'),
                subtitle: Text(
                  _segments.length == 1
                      ? '1 segment'
                      : '${_segments.length} segments',
                ),
                children: [
                  for (final segment in _segments)
                    _TranscriptSegment(
                      segment: segment,
                      time: time,
                      retry: () => retryTranscription(segment['id']! as String),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, dynamic>? _summaryMap(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    try {
      return jsonDecode(value) as Map<String, dynamic>;
    } on Object {
      return null;
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final segmentCount = _segments.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete transcript?'),
        content: Text(
          'This removes the local encrypted recording and its transcript'
          '${segmentCount > 1 ? ' ($segmentCount segments)' : ''}. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) onDelete();
  }

  String? _string(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty || text == 'null' ? null : text;
  }

  bool _retryable(Object? state) => state == 'FAILED' || state == 'RETRY_WAIT';

  List<Map<Object?, Object?>> get _segments {
    final values = item['segments'];
    if (values is List) {
      return values
          .map((value) => Map<Object?, Object?>.from(value! as Map))
          .toList();
    }
    return [item];
  }
}

class _TranscriptSegment extends StatelessWidget {
  const _TranscriptSegment({
    required this.segment,
    required this.time,
    required this.retry,
  });

  final Map<Object?, Object?> segment;
  final String Function(int) time;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          time(segment['startedAt']! as int),
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 6),
        _StateChip(
          label: segment['transcriptionState'] as String? ?? 'PENDING',
        ),
        const SizedBox(height: 6),
        CopyableText(
          segment['transcriptionState'] == 'EMPTY'
              ? 'No human voice detected.'
              : segment['transcript'] as String? ?? 'No transcript yet.',
          label: 'Transcript',
        ),
        if (segment['transcriptionError'] case final String message)
          _ErrorText(message: message),
        if (segment['transcriptionState'] == 'FAILED' ||
            segment['transcriptionState'] == 'RETRY_WAIT')
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: retry,
              icon: const Icon(Icons.refresh),
              label: const Text('Resubmit transcription'),
            ),
          ),
      ],
    ),
  );
}

class _SummaryContent extends StatelessWidget {
  const _SummaryContent({required this.value, required this.parsed});

  final String? value;
  final Map<String, dynamic>? parsed;

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.trim().isEmpty) {
      return const Text('No summary yet.');
    }
    if (parsed == null) {
      return CopyableText(value!, label: 'Summary');
    }
    final summary = _text(parsed!['summary']);
    final tags = <String>{
      ..._strings(parsed!['keywords']),
      ..._strings(parsed!['secondary_topics']),
      ..._strings(parsed!['topics']),
    }.take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (summary != null)
          CopyableText(
            summary,
            label: 'Summary',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(height: 1.45),
          ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [for (final tag in tags) Chip(label: Text(tag))],
          ),
        ],
        _SummaryList(
          title: 'Decisions',
          values: _strings(parsed!['decisions']),
        ),
        _SummaryList(
          title: 'Action items',
          values: _strings(parsed!['action_items']),
        ),
        _SummaryList(
          title: 'Questions',
          values: _strings(parsed!['questions']),
        ),
        _SummaryList(
          title: 'Uncertainties',
          values: _strings(parsed!['uncertainties']),
        ),
      ],
    );
  }

  String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty || text == 'null' ? null : text;
  }

  List<String> _strings(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) {
          if (item is Map) {
            return item['text']?.toString() ??
                item['task']?.toString() ??
                item['description']?.toString() ??
                item.toString();
          }
          return item.toString();
        })
        .where((item) => item.trim().isNotEmpty)
        .toList();
  }
}

class _SummaryList extends StatelessWidget {
  const _SummaryList({required this.title, required this.values});

  final String title;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          for (final value in values)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  '),
                  Expanded(child: Text(value)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Chip(
    avatar: Icon(
      label == 'COMPLETE' ? Icons.check_circle_outline : Icons.schedule,
      size: 17,
    ),
    label: Text(label.toLowerCase()),
    visualDensity: VisualDensity.compact,
  );
}

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Text(message, style: const TextStyle(color: Colors.redAccent)),
  );
}
