import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const nativeCommands = MethodChannel('recall_whisper/recorder');
final workflowActivity = WorkflowActivity();

class WorkflowActivity
    extends ValueNotifier<({bool transcribing, bool summarizing})> {
  WorkflowActivity() : super((transcribing: false, summarizing: false));

  Timer? _timer;

  Future<void> refresh() async {
    try {
      final status = await nativeCommands.invokeMapMethod<Object?, Object?>(
        'processingStatus',
      );
      final next = (
        transcribing: status?['transcribing'] == true,
        summarizing: status?['summarizing'] == true,
      );
      if (next == value) {
        notifyListeners();
      } else {
        value = next;
      }
      _timer?.cancel();
      if (value.transcribing || value.summarizing) {
        _timer = Timer(const Duration(seconds: 1), refresh);
      }
    } on Object {
      value = (transcribing: false, summarizing: false);
    }
  }

  Future<void> run(String command) async {
    value = (
      transcribing: command == 'transcribeNow' || value.transcribing,
      summarizing: command == 'summarizeNow' || value.summarizing,
    );
    try {
      await nativeCommands.invokeMethod(command);
    } finally {
      await refresh();
    }
  }

  Future<void> stop(String command) async {
    try {
      await nativeCommands.invokeMethod(command);
    } finally {
      await refresh();
    }
  }
}

void main() => runApp(const RecallWhisperApp());

class RecallWhisperApp extends StatelessWidget {
  const RecallWhisperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RecallWhisper',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff47655a),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xff101512),
        useMaterial3: true,
      ),
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    workflowActivity.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) workflowActivity.refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: switch (index) {
      0 => const RecorderPage(),
      1 => const TimelinePage(),
      _ => const TopicsPage(),
    },
    bottomNavigationBar: NavigationBar(
      selectedIndex: index,
      onDestinationSelected: (value) => setState(() => index = value),
      labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.mic_none),
          selectedIcon: Icon(Icons.mic),
          label: 'Recorder',
        ),
        NavigationDestination(
          icon: Icon(Icons.notes_outlined),
          selectedIcon: Icon(Icons.notes),
          label: 'Transcripts',
        ),
        NavigationDestination(
          icon: Icon(Icons.topic_outlined),
          selectedIcon: Icon(Icons.topic),
          label: 'Topics',
        ),
      ],
    ),
  );
}

class RecorderPage extends StatefulWidget {
  const RecorderPage({super.key});

  @override
  State<RecorderPage> createState() => _RecorderPageState();
}

class _RecorderPageState extends State<RecorderPage> {
  static const _events = EventChannel('recall_whisper/recorder_events');

  StreamSubscription<Object?>? _subscription;
  String _state = 'STOPPED';
  String? _playingId;
  String? _error;
  List<Map<Object?, Object?>> _segments = const [];
  int _refreshRequest = 0;

  @override
  void initState() {
    super.initState();
    _subscription = _events.receiveBroadcastStream().listen(_onEvent);
    workflowActivity.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    workflowActivity.removeListener(_refresh);
    _subscription?.cancel();
    super.dispose();
  }

  void _onEvent(Object? raw) {
    final event = Map<Object?, Object?>.from(raw! as Map);
    if (!mounted) return;
    setState(() {
      if (event['type'] == 'state') _state = event['state']! as String;
      if (event['type'] == 'error') _error = event['message']! as String;
      if (event['type'] == 'playback') {
        _playingId = event['segmentId'] as String?;
      }
    });
    if (event['type'] == 'segment') _refresh();
  }

  Future<void> _refresh() async {
    final request = ++_refreshRequest;
    try {
      final status = await nativeCommands.invokeMapMethod<Object?, Object?>(
        'status',
      );
      final segments = await nativeCommands.invokeListMethod<Object?>(
        'segments',
      );
      if (!mounted || request != _refreshRequest) return;
      setState(() {
        _state = status?['state'] as String? ?? 'STOPPED';
        _segments = (segments ?? const [])
            .map((e) => Map<Object?, Object?>.from(e! as Map))
            .toList();
      });
    } on PlatformException catch (error) {
      if (mounted && request == _refreshRequest) {
        setState(() => _error = error.message);
      }
    }
  }

  Future<void> _command(String command) async {
    setState(() => _error = null);
    try {
      if (command == 'transcribeNow' || command == 'summarizeNow') {
        await workflowActivity.run(command);
      } else {
        await nativeCommands.invokeMethod(command);
      }
      await _refresh();
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _state == 'LISTENING' || _state == 'RECORDING';
    final recording = _state == 'RECORDING';
    return Scaffold(
      appBar: AppBar(
        title: const Text('RecallWhisper'),
        actions: [
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
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Semantics(
              liveRegion: true,
              label: 'Recorder status: $_state',
              child: Card(
                color: recording
                    ? const Color(0xff5d2828)
                    : const Color(0xff1b2621),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        recording ? Icons.graphic_eq : Icons.mic_none,
                        size: 64,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _state,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        recording
                            ? 'Speech is being saved'
                            : active
                            ? 'Listening locally · silence is not saved'
                            : 'Microphone is closed',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _command(active ? 'pause' : 'start'),
              icon: Icon(active ? Icons.pause : Icons.mic),
              label: Text(active ? 'Pause' : 'Start listening'),
            ),
            if (_state != 'STOPPED')
              TextButton.icon(
                onPressed: () => _command('stop'),
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              ),
            const SizedBox(height: 28),
            Text(
              'Saved segments',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                ValueListenableBuilder(
                  valueListenable: workflowActivity,
                  builder: (context, activity, _) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        onPressed: activity.transcribing
                            ? null
                            : () => _command('transcribeNow'),
                        icon: activity.transcribing
                            ? const _WorkingIndicator()
                            : const Icon(Icons.graphic_eq),
                        label: Text(
                          activity.transcribing
                              ? 'Transcribing…'
                              : 'Transcribe',
                        ),
                      ),
                      TextButton.icon(
                        onPressed: activity.summarizing
                            ? null
                            : () => _command('summarizeNow'),
                        icon: activity.summarizing
                            ? const _WorkingIndicator()
                            : const Icon(Icons.summarize_outlined),
                        label: Text(
                          activity.summarizing ? 'Summarizing…' : 'Summarize',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            ValueListenableBuilder(
              valueListenable: workflowActivity,
              builder: (context, activity, _) =>
                  _WorkflowBanner(activity: activity),
            ),
            const SizedBox(height: 8),
            if (_segments.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('No speech segments yet.'),
                ),
              ),
            for (final segment in _segments)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.multitrack_audio),
                  title: Text(_formatTime(segment['startedAt']! as int)),
                  subtitle: Text(
                    '${_formatDuration(segment['durationMs']! as int)}'
                    ' · encrypted · ${(segment['sizeBytes']! as int) ~/ 1024} KB\n'
                    '${segment['uploadState']} · ${segment['serverState']}',
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: _playingId == segment['id']
                            ? 'Stop playback'
                            : 'Play recording',
                        icon: Icon(
                          _playingId == segment['id']
                              ? Icons.stop_circle_outlined
                              : Icons.play_circle_outline,
                        ),
                        onPressed: () async {
                          if (_playingId == segment['id']) {
                            await nativeCommands.invokeMethod('stopPlayback');
                          } else {
                            await nativeCommands.invokeMethod('playSegment', {
                              'id': segment['id'],
                            });
                          }
                        },
                      ),
                      IconButton(
                        tooltip: 'Delete local segment',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await nativeCommands.invokeMethod('deleteSegment', {
                            'id': segment['id'],
                          });
                          await _refresh();
                        },
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(int milliseconds) {
    final value = DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')} '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}:'
        '${value.second.toString().padLeft(2, '0')}';
  }

  String _formatDuration(int milliseconds) =>
      '${(milliseconds / 1000).toStringAsFixed(1)} seconds';
}

class _WorkingIndicator extends SizedBox {
  const _WorkingIndicator()
    : super(
        width: 18,
        height: 18,
        child: const CircularProgressIndicator(strokeWidth: 2),
      );
}

class _ButtonLabel extends StatelessWidget {
  const _ButtonLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) =>
      FittedBox(fit: BoxFit.scaleDown, child: Text(text));
}

class _WorkflowBanner extends StatelessWidget {
  const _WorkflowBanner({required this.activity});

  final ({bool transcribing, bool summarizing}) activity;

  @override
  Widget build(BuildContext context) {
    if (!activity.transcribing && !activity.summarizing) {
      return const SizedBox.shrink();
    }
    final label = activity.transcribing && activity.summarizing
        ? 'Transcription and summary are queued or running'
        : activity.transcribing
        ? 'Transcription is queued or running'
        : 'Summary is queued or running';
    return Semantics(
      liveRegion: true,
      label: label,
      child: Card(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const _WorkingIndicator(),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$label…',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TimelinePage extends StatefulWidget {
  const TimelinePage({super.key});

  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  List<Map<Object?, Object?>> items = const [];
  String? error;
  int _refreshRequest = 0;

  @override
  void initState() {
    super.initState();
    workflowActivity.addListener(refresh);
    refresh();
  }

  @override
  void dispose() {
    workflowActivity.removeListener(refresh);
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
    final id = item['id']! as String;
    try {
      if (item['isEpisode'] == true) {
        await nativeCommands.invokeMethod('deleteEpisode', {'id': id});
      } else {
        await nativeCommands.invokeMethod('deleteSegment', {'id': id});
      }
      await refresh();
    } on PlatformException catch (exception) {
      if (mounted) setState(() => error = exception.message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Transcripts'),
      actions: [
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
    ),
    body: RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ValueListenableBuilder(
            valueListenable: workflowActivity,
            builder: (context, activity, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _WorkflowBanner(activity: activity),
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
                            Text(
                              'Queue processing',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => activity.transcribing
                                    ? stop('stopTranscription')
                                    : run('transcribeNow'),
                                icon: Icon(
                                  activity.transcribing
                                      ? Icons.stop
                                      : Icons.graphic_eq,
                                ),
                                label: _ButtonLabel(
                                  text: activity.transcribing
                                      ? 'Stop transcription'
                                      : 'Transcribe pending',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: () => activity.summarizing
                                    ? stop('stopSummary')
                                    : run('summarizeNow'),
                                icon: Icon(
                                  activity.summarizing
                                      ? Icons.stop
                                      : Icons.summarize_outlined,
                                ),
                                label: _ButtonLabel(
                                  text: activity.summarizing
                                      ? 'Stop summary'
                                      : 'Summarize pending',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    retryAll('retryFailedTranscriptions'),
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const _ButtonLabel(
                                  text: 'Retry failed transcripts',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    retryAll('retryFailedSummaries'),
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const _ButtonLabel(
                                  text: 'Retry failed summaries',
                                ),
                              ),
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
                time: _time,
                retryTranscription: (id) => retry('retryTranscription', id),
                retrySummary: () =>
                    retry('retrySummary', items[index]['id']! as String),
                onDelete: () => deleteTranscript(items[index]),
              ),
            ),
        ],
      ),
    ),
  );

  String _time(int milliseconds) {
    final value = DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')} '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}:'
        '${value.second.toString().padLeft(2, '0')}';
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
  });

  final Map<Object?, Object?> item;
  final String Function(int) time;
  final ValueChanged<String> retryTranscription;
  final VoidCallback retrySummary;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final summary = _summaryMap(item['summary'] as String?);
    final title =
        _string(summary?['local_title']) ??
        _string(summary?['title']) ??
        'Recording summary';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                IconButton(
                  tooltip: 'Delete transcript',
                  onPressed: () => _confirmDelete(context),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SummaryContent(value: item['summary'] as String?, parsed: summary),
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
        SelectableText(
          segment['transcriptionState'] == 'EMPTY'
              ? 'No human voice detected.'
              : segment['transcript'] as String? ?? 'No transcript yet.',
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
    if (parsed == null) return SelectableText(value!);
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
          SelectableText(
            summary,
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

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final controller = TextEditingController();
  List<Map<Object?, Object?>> results = const [];
  String? error;
  String _query = '';
  int _searchRequest = 0;

  @override
  void initState() {
    super.initState();
    workflowActivity.addListener(_refreshSearch);
  }

  void _refreshSearch() {
    if (_query.isNotEmpty) search(_query);
  }

  Future<void> search([String? existingQuery]) async {
    final query = existingQuery ?? controller.text.trim();
    if (query.isEmpty) return;
    _query = query;
    final request = ++_searchRequest;
    try {
      final values = await nativeCommands.invokeListMethod<Object?>('search', {
        'query': query,
      });
      if (mounted && request == _searchRequest) {
        setState(() {
          results = (values ?? const [])
              .map((value) => Map<Object?, Object?>.from(value! as Map))
              .toList();
          error = null;
        });
      }
    } on PlatformException catch (exception) {
      if (mounted && request == _searchRequest) {
        setState(() => error = exception.message);
      }
    }
  }

  @override
  void dispose() {
    workflowActivity.removeListener(_refreshSearch);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Search and recall')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SearchBar(
          controller: controller,
          hintText: 'Names, topics, decisions, exact phrases',
          onSubmitted: (_) => search(),
          trailing: [
            IconButton(onPressed: search, icon: const Icon(Icons.search)),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              error!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        const SizedBox(height: 16),
        if (results.isEmpty) const Text('No matching transcript evidence.'),
        for (final result in results)
          Card(
            child: ListTile(
              title: Text(result['title'] as String? ?? 'Conversation'),
              subtitle: Text(result['excerpt'] as String? ?? ''),
              leading: const Icon(Icons.format_quote),
            ),
          ),
      ],
    ),
  );
}

class TopicsPage extends StatefulWidget {
  const TopicsPage({super.key});

  @override
  State<TopicsPage> createState() => _TopicsPageState();
}

class _TopicsPageState extends State<TopicsPage> {
  List<Map<Object?, Object?>> topics = const [];
  String? error;
  int _refreshRequest = 0;

  @override
  void initState() {
    super.initState();
    workflowActivity.addListener(refresh);
    refresh();
  }

  @override
  void dispose() {
    workflowActivity.removeListener(refresh);
    super.dispose();
  }

  Future<void> refresh() async {
    final request = ++_refreshRequest;
    try {
      final values = await nativeCommands.invokeListMethod<Object?>('topics');
      if (!mounted || request != _refreshRequest) return;
      setState(() {
        topics = (values ?? const [])
            .map((value) => Map<Object?, Object?>.from(value! as Map))
            .toList();
        error = null;
      });
    } on PlatformException catch (exception) {
      if (mounted && request == _refreshRequest) {
        setState(() => error = exception.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Topics'),
      actions: [
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
    ),
    body: RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ValueListenableBuilder(
            valueListenable: workflowActivity,
            builder: (context, activity, _) =>
                _WorkflowBanner(activity: activity),
          ),
          const Text(
            'Recurring subjects are grouped here while every separate occurrence keeps its own time range.',
          ),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.redAccent)),
          const SizedBox(height: 12),
          if (topics.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'No topics yet. Transcribe recordings, then run Summarize.',
                ),
              ),
            ),
          for (final topic in topics)
            Card(
              child: ExpansionTile(
                leading: const Icon(Icons.topic_outlined),
                title: Text(topic['title'] as String),
                subtitle: Text(
                  '${_formatTopicTime(topic['firstSeen'] as int)} – '
                  '${_formatTopicTime(topic['lastSeen'] as int)}',
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(topic['description'] as String),
                  const SizedBox(height: 8),
                  Text(
                    topic['currentSummary'] as String,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const Divider(height: 24),
                  for (final rawEpisode
                      in (topic['episodes'] as List<Object?>? ?? const []))
                    _EpisodeTile(
                      episode: Map<Object?, Object?>.from(rawEpisode! as Map),
                    ),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  String _formatTopicTime(int milliseconds) {
    final value = DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
    return '${value.month}/${value.day} '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({required this.episode});

  final Map<Object?, Object?> episode;

  @override
  Widget build(BuildContext context) {
    final start = DateTime.fromMillisecondsSinceEpoch(
      episode['startedAt'] as int,
    ).toLocal();
    final end = DateTime.fromMillisecondsSinceEpoch(
      episode['endedAt'] as int,
    ).toLocal();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            episode['title'] as String,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            '${start.year}-${start.month.toString().padLeft(2, '0')}-'
            '${start.day.toString().padLeft(2, '0')} '
            '${start.hour.toString().padLeft(2, '0')}:'
            '${start.minute.toString().padLeft(2, '0')}–'
            '${end.hour.toString().padLeft(2, '0')}:'
            '${end.minute.toString().padLeft(2, '0')} · '
            '${episode['status']}',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 4),
          SelectableText(_episodeSummary(episode['summary'] as String)),
        ],
      ),
    );
  }

  String _episodeSummary(String value) {
    try {
      return (jsonDecode(value) as Map<String, dynamic>)['summary'] as String;
    } on Object {
      return value;
    }
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final transcriptionUrl = TextEditingController();
  final transcriptionToken = TextEditingController();
  final transcriptionModel = TextEditingController();
  final summarizationUrl = TextEditingController();
  final summarizationToken = TextEditingController();
  final summarizationModel = TextEditingController();
  final summaryLanguage = TextEditingController();
  bool cellular = false;
  bool allowHttp = false;
  int trailingSilenceMs = 30000;
  int episodeGapMinutes = 5;
  int episodeMaxMinutes = 30;
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final config = await nativeCommands.invokeMapMethod<Object?, Object?>(
      'config',
    );
    if (!mounted) return;
    transcriptionUrl.text = config?['transcriptionUrl'] as String? ?? '';
    transcriptionToken.text = config?['transcriptionToken'] as String? ?? '';
    transcriptionModel.text =
        config?['transcriptionModel'] as String? ?? 'whisper-1';
    summarizationUrl.text = config?['summarizationUrl'] as String? ?? '';
    summarizationToken.text = config?['summarizationToken'] as String? ?? '';
    summarizationModel.text = config?['summarizationModel'] as String? ?? '';
    summaryLanguage.text =
        config?['summaryLanguage'] as String? ?? 'Same as transcript';
    if (mounted) {
      setState(() {
        cellular = config?['cellular'] as bool? ?? false;
        allowHttp = config?['allowHttp'] as bool? ?? false;
        trailingSilenceMs =
            config?['trailingSilenceMs'] as int? ?? trailingSilenceMs;
        episodeGapMinutes =
            config?['episodeGapMinutes'] as int? ?? episodeGapMinutes;
        episodeMaxMinutes =
            config?['episodeMaxMinutes'] as int? ?? episodeMaxMinutes;
        loaded = true;
      });
    }
  }

  Future<void> save() async {
    await nativeCommands.invokeMethod('saveConfig', {
      'cellular': cellular,
      'allowHttp': allowHttp,
      'trailingSilenceMs': trailingSilenceMs,
      'transcriptionUrl': transcriptionUrl.text.trim(),
      'transcriptionToken': transcriptionToken.text,
      'transcriptionModel': transcriptionModel.text.trim(),
      'summarizationUrl': summarizationUrl.text.trim(),
      'summarizationToken': summarizationToken.text,
      'summarizationModel': summarizationModel.text.trim(),
      'summaryLanguage': summaryLanguage.text.trim(),
      'episodeGapMinutes': episodeGapMinutes,
      'episodeMaxMinutes': episodeMaxMinutes,
    });
    await nativeCommands.invokeMethod('sync');
    await workflowActivity.refresh();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Settings saved')));
    }
  }

  @override
  void dispose() {
    transcriptionUrl.dispose();
    transcriptionToken.dispose();
    transcriptionModel.dispose();
    summarizationUrl.dispose();
    summarizationToken.dispose();
    summarizationModel.dispose();
    summaryLanguage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Server and privacy')),
    body: !loaded
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow insecure HTTP'),
                subtitle: Text(
                  allowHttp
                      ? 'Enabled: API credentials and audio may cross the network unencrypted.'
                      : 'Disabled: processing APIs must use HTTPS.',
                  style: TextStyle(
                    color: allowHttp ? Colors.orangeAccent : null,
                  ),
                ),
                value: allowHttp,
                onChanged: (value) => setState(() => allowHttp = value),
              ),
              const SizedBox(height: 28),
              Text(
                'Transcription server',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: transcriptionUrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'OpenAI-compatible transcription URL',
                  hintText: 'https://asr.example.com/v1',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: transcriptionToken,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Transcription token',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: transcriptionModel,
                decoration: const InputDecoration(
                  labelText: 'Transcription model',
                  hintText: 'whisper-1',
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Summarization server',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: summarizationUrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'OpenAI-compatible summarization URL',
                  hintText: 'https://llm.example.com/v1',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: summarizationToken,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Summarization token',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: summarizationModel,
                decoration: const InputDecoration(
                  labelText: 'Summarization model',
                  hintText: 'qwen3:8b',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: summaryLanguage,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Summary language',
                  hintText: 'Same as transcript, English, Simplified Chinese…',
                  helperText:
                      'Used for titles, summaries, decisions, and actions',
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Topic episodes',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('New episode after inactivity'),
                subtitle: Text('$episodeGapMinutes minutes between recordings'),
              ),
              Slider(
                min: 3,
                max: 10,
                divisions: 7,
                value: episodeGapMinutes.toDouble(),
                label: '$episodeGapMinutes min',
                onChanged: (value) =>
                    setState(() => episodeGapMinutes = value.round()),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Maximum episode length'),
                subtitle: Text('$episodeMaxMinutes minutes'),
              ),
              Slider(
                min: 10,
                max: 60,
                divisions: 10,
                value: episodeMaxMinutes.toDouble(),
                label: '$episodeMaxMinutes min',
                onChanged: (value) =>
                    setState(() => episodeMaxMinutes = value.round()),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Upload over cellular'),
                subtitle: const Text('Wi-Fi only is the privacy default'),
                value: cellular,
                onChanged: (value) => setState(() => cellular = value),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Conversation pause tolerance'),
                subtitle: Text(
                  '${(trailingSilenceMs / 1000).round()} seconds before closing a recording',
                ),
              ),
              Slider(
                min: 5,
                max: 60,
                divisions: 11,
                value: trailingSilenceMs / 1000,
                label: '${(trailingSilenceMs / 1000).round()} s',
                onChanged: (value) =>
                    setState(() => trailingSilenceMs = (value * 1000).round()),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: save, child: const Text('Save')),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    await nativeCommands.invokeMethod('exportData');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('JSON export saved')),
                      );
                    }
                  } on PlatformException catch (error) {
                    if (error.code != 'export_cancelled' && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(error.message ?? 'Export failed'),
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.download_outlined),
                label: const Text('Export all data as JSON'),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.bug_report_outlined),
                  title: const Text('Debug and API playground'),
                  subtitle: const Text(
                    'Models, system prompt, parameters, and test requests',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const DebugPage())),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: const Text('Debug log'),
                  subtitle: const Text(
                    'Recorder and processing events stored on this device',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DebugLogPage()),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Audio is AES-256-GCM encrypted in private app storage. '
                'Transcripts, summaries, metadata, and audio remain on this phone. '
                'Only audio sent for transcription and transcript text sent for '
                'summarization leave the device.',
              ),
            ],
          ),
  );
}

class DebugLogPage extends StatefulWidget {
  const DebugLogPage({super.key});

  @override
  State<DebugLogPage> createState() => _DebugLogPageState();
}

class _DebugLogPageState extends State<DebugLogPage> {
  String logs = '';
  String? error;
  bool busy = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await nativeCommands.invokeMethod<String>('debugLogs');
      if (mounted) setState(() => logs = value ?? '');
    } on PlatformException catch (exception) {
      if (mounted) setState(() => error = exception.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> clear() async {
    await nativeCommands.invokeMethod('debugClearLogs');
    if (mounted) setState(() => logs = '');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Debug log'),
      actions: [
        IconButton(
          tooltip: 'Copy log',
          onPressed: logs.isEmpty
              ? null
              : () => Clipboard.setData(ClipboardData(text: logs)),
          icon: const Icon(Icons.copy_outlined),
        ),
        IconButton(
          tooltip: 'Refresh log',
          onPressed: load,
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: 'Clear log',
          onPressed: logs.isEmpty ? null : clear,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    ),
    body: busy
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? Center(child: Text(error!))
        : logs.isEmpty
        ? const Center(child: Text('No debug events yet.'))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: SelectableText(
              logs,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
  );
}

class DebugPage extends StatefulWidget {
  const DebugPage({super.key});

  @override
  State<DebugPage> createState() => _DebugPageState();
}

class _DebugPageState extends State<DebugPage> {
  final formKey = GlobalKey<FormState>();
  final prompt = TextEditingController();
  final input = TextEditingController(
    text: 'Summarize this text and list the important decisions:\n',
  );
  final model = TextEditingController();
  final maxTokens = TextEditingController(text: '1000');
  List<String> models = const [];
  double temperature = 0.1;
  double topP = 1;
  double frequencyPenalty = 0;
  double presencePenalty = 0;
  bool jsonMode = false;
  bool busy = false;
  String? response;
  String? error;
  String? transcriptionHealth;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await nativeCommands.invokeMapMethod<Object?, Object?>(
        'debugLoad',
      );
      if (!mounted) return;
      setState(() {
        models = (value?['models'] as List<Object?>? ?? const [])
            .cast<String>();
        prompt.text = value?['systemPrompt'] as String? ?? '';
        if (model.text.isEmpty && models.isNotEmpty) model.text = models.first;
      });
    } on PlatformException catch (exception) {
      if (mounted) setState(() => error = exception.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> savePrompt() async {
    if (prompt.text.trim().isEmpty) {
      setState(() => error = 'System prompt cannot be empty.');
      return;
    }
    await run(() async {
      await nativeCommands.invokeMethod('debugSavePrompt', {
        'systemPrompt': prompt.text.trim(),
      });
      return 'System prompt saved.';
    });
  }

  Future<void> checkTranscriptionHealth() async {
    setState(() {
      busy = true;
      transcriptionHealth = null;
    });
    try {
      final value = await nativeCommands.invokeMapMethod<Object?, Object?>(
        'debugTranscriptionHealth',
      );
      if (mounted) {
        final models = (value?['models'] as List<Object?>? ?? const []).join(
          ', ',
        );
        setState(() {
          transcriptionHealth =
              'Healthy · ${value?['elapsed_ms']} ms'
              '${models.isEmpty ? '' : '\nModels: $models'}';
        });
      }
    } on PlatformException catch (exception) {
      if (mounted) {
        setState(() {
          transcriptionHealth =
              'Unhealthy · ${exception.message ?? 'Request failed'}';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> send() async {
    if (!formKey.currentState!.validate()) return;
    await run(() async {
      final value = await nativeCommands
          .invokeMapMethod<Object?, Object?>('debugChat', {
            'text': input.text.trim(),
            'system_prompt': prompt.text.trim(),
            'model': model.text.trim(),
            'temperature': temperature,
            'top_p': topP,
            'max_tokens': int.parse(maxTokens.text),
            'frequency_penalty': frequencyPenalty,
            'presence_penalty': presencePenalty,
            'json_mode': jsonMode,
          });
      return '${value?['model']} · ${value?['elapsed_ms']} ms\n\n'
          '${value?['output']}';
    });
  }

  Future<void> run(Future<String> Function() operation) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await operation();
      if (mounted) setState(() => response = value);
    } on PlatformException catch (exception) {
      if (mounted) setState(() => error = exception.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    prompt.dispose();
    input.dispose();
    model.dispose();
    maxTokens.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Debug playground'),
      actions: [
        IconButton(
          tooltip: 'Reload models',
          onPressed: busy ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: ListTile(
              leading: Icon(
                transcriptionHealth?.startsWith('Healthy') == true
                    ? Icons.check_circle_outline
                    : Icons.health_and_safety_outlined,
                color: transcriptionHealth?.startsWith('Healthy') == true
                    ? Colors.greenAccent
                    : null,
              ),
              title: const Text('Transcription server health'),
              subtitle: transcriptionHealth == null
                  ? const Text('Checks authentication and model discovery')
                  : Text(transcriptionHealth!),
              trailing: FilledButton(
                onPressed: busy ? null : checkTranscriptionHealth,
                child: const Text('Check'),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Available models',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (models.isEmpty)
            const Text('No models loaded. Check the summarization endpoint.')
          else
            Wrap(
              spacing: 8,
              children: [
                for (final value in models)
                  ChoiceChip(
                    label: Text(value),
                    selected: model.text == value,
                    onSelected: (_) => setState(() => model.text = value),
                  ),
              ],
            ),
          const SizedBox(height: 20),
          TextFormField(
            controller: model,
            decoration: const InputDecoration(labelText: 'Model'),
            validator: requiredField,
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: prompt,
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(labelText: 'System prompt'),
            validator: requiredField,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: busy ? null : savePrompt,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save system prompt'),
            ),
          ),
          TextFormField(
            controller: input,
            minLines: 6,
            maxLines: 16,
            decoration: const InputDecoration(labelText: 'Test text'),
            validator: requiredField,
          ),
          const SizedBox(height: 20),
          parameterSlider(
            'Temperature',
            temperature,
            0,
            2,
            (value) => temperature = value,
          ),
          parameterSlider('Top P', topP, 0.05, 1, (value) => topP = value),
          parameterSlider(
            'Frequency penalty',
            frequencyPenalty,
            -2,
            2,
            (value) => frequencyPenalty = value,
          ),
          parameterSlider(
            'Presence penalty',
            presencePenalty,
            -2,
            2,
            (value) => presencePenalty = value,
          ),
          TextFormField(
            controller: maxTokens,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Maximum output tokens',
            ),
            validator: (value) {
              final parsed = int.tryParse(value ?? '');
              return parsed == null || parsed < 1 || parsed > 32768
                  ? 'Enter a value from 1 to 32768.'
                  : null;
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('JSON response mode'),
            value: jsonMode,
            onChanged: (value) => setState(() => jsonMode = value),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: busy ? null : send,
            icon: const Icon(Icons.send),
            label: const Text('Send test request'),
          ),
          if (busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          if (error != null) ...[
            const SizedBox(height: 16),
            Text(error!, style: const TextStyle(color: Colors.redAccent)),
          ],
          if (response != null) ...[
            const SizedBox(height: 24),
            Text('Response', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(response!),
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Widget parameterSlider(
    String label,
    double value,
    double minimum,
    double maximum,
    ValueChanged<double> changed,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$label: ${value.toStringAsFixed(2)}'),
      Slider(
        min: minimum,
        max: maximum,
        divisions: 20,
        value: value,
        onChanged: (next) => setState(() => changed(next)),
      ),
    ],
  );

  String? requiredField(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required.' : null;
}
