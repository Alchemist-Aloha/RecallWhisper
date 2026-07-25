import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
      home: const RecorderPage(),
    );
  }
}

class RecorderPage extends StatefulWidget {
  const RecorderPage({super.key});

  @override
  State<RecorderPage> createState() => _RecorderPageState();
}

class _RecorderPageState extends State<RecorderPage>
    with WidgetsBindingObserver {
  static const _commands = MethodChannel('recall_whisper/recorder');
  static const _events = EventChannel('recall_whisper/recorder_events');

  StreamSubscription<Object?>? _subscription;
  String _state = 'STOPPED';
  String? _error;
  List<Map<Object?, Object?>> _segments = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = _events.receiveBroadcastStream().listen(_onEvent);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _onEvent(Object? raw) {
    final event = Map<Object?, Object?>.from(raw! as Map);
    if (!mounted) return;
    setState(() {
      if (event['type'] == 'state') _state = event['state']! as String;
      if (event['type'] == 'error') _error = event['message']! as String;
    });
    if (event['type'] == 'segment') _refresh();
  }

  Future<void> _refresh() async {
    try {
      final status = await _commands.invokeMapMethod<Object?, Object?>(
        'status',
      );
      final segments = await _commands.invokeListMethod<Object?>('segments');
      if (!mounted) return;
      setState(() {
        _state = status?['state'] as String? ?? 'STOPPED';
        _segments = (segments ?? const [])
            .map((e) => Map<Object?, Object?>.from(e! as Map))
            .toList();
      });
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _command(String command) async {
    setState(() => _error = null);
    try {
      await _commands.invokeMethod(command);
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
                    ' · WAV · ${(segment['sizeBytes']! as int) ~/ 1024} KB',
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
