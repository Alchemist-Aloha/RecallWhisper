import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../channels.dart';
import '../format.dart';
import '../widgets/status_views.dart';
import '../widgets/workflow.dart';
import 'search_page.dart';
import 'settings_page.dart';

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
              ErrorText(message: _error!),
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
                            ? const WorkingIndicator()
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
                            ? const WorkingIndicator()
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
                  WorkflowBanner(activity: activity),
            ),
            const SizedBox(height: 8),
            if (_segments.isEmpty)
              const EmptyState(
                icon: Icons.multitrack_audio,
                title: 'No speech segments yet.',
                message: 'Recordings you keep while listening appear here.',
              ),
            for (final segment in _segments)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.multitrack_audio),
                  title: Text(formatTimestamp(segment['startedAt']! as int)),
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

  String _formatDuration(int milliseconds) =>
      '${(milliseconds / 1000).toStringAsFixed(1)} seconds';
}
