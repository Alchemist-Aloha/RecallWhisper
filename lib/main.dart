import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const nativeCommands = MethodChannel('recall_whisper/recorder');

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
  static const _events = EventChannel('recall_whisper/recorder_events');

  StreamSubscription<Object?>? _subscription;
  String _state = 'STOPPED';
  String? _playingId;
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
      if (event['type'] == 'playback') {
        _playingId = event['segmentId'] as String?;
      }
    });
    if (event['type'] == 'segment') _refresh();
  }

  Future<void> _refresh() async {
    try {
      final status = await nativeCommands.invokeMapMethod<Object?, Object?>(
        'status',
      );
      final segments = await nativeCommands.invokeListMethod<Object?>(
        'segments',
      );
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
      await nativeCommands.invokeMethod(command);
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Saved segments',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _command('sync'),
                  icon: const Icon(Icons.sync),
                  label: const Text('Process now'),
                ),
              ],
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

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final controller = TextEditingController();
  List<Map<Object?, Object?>> results = const [];
  String? error;

  Future<void> search() async {
    if (controller.text.trim().isEmpty) return;
    try {
      final values = await nativeCommands.invokeListMethod<Object?>('search', {
        'query': controller.text.trim(),
      });
      if (mounted) {
        setState(() {
          results = (values ?? const [])
              .map((value) => Map<Object?, Object?>.from(value! as Map))
              .toList();
          error = null;
        });
      }
    } on PlatformException catch (exception) {
      if (mounted) setState(() => error = exception.message);
    }
  }

  @override
  void dispose() {
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
  bool cellular = false;
  bool allowHttp = false;
  int trailingSilenceMs = 30000;
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
    transcriptionUrl.text = config?['transcriptionUrl'] as String? ?? '';
    transcriptionToken.text = config?['transcriptionToken'] as String? ?? '';
    transcriptionModel.text =
        config?['transcriptionModel'] as String? ?? 'whisper-1';
    summarizationUrl.text = config?['summarizationUrl'] as String? ?? '';
    summarizationToken.text = config?['summarizationToken'] as String? ?? '';
    summarizationModel.text = config?['summarizationModel'] as String? ?? '';
    if (mounted) {
      setState(() {
        cellular = config?['cellular'] as bool? ?? false;
        allowHttp = config?['allowHttp'] as bool? ?? false;
        trailingSilenceMs =
            config?['trailingSilenceMs'] as int? ?? trailingSilenceMs;
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
    });
    await nativeCommands.invokeMethod('sync');
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
