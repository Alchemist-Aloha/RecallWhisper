import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../channels.dart';

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
