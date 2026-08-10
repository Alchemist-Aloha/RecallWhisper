import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../channels.dart';

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
