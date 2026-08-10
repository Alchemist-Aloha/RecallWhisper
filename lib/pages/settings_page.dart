import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../channels.dart';
import 'debug_log_page.dart';
import 'debug_page.dart';

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
