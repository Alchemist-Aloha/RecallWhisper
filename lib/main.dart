import 'package:flutter/material.dart';

import 'channels.dart';
import 'pages/recorder_page.dart';
import 'pages/timeline_page.dart';
import 'pages/topics_page.dart';

export 'channels.dart';
export 'pages/debug_log_page.dart';
export 'pages/debug_page.dart';
export 'pages/recorder_page.dart';
export 'pages/search_page.dart';
export 'pages/settings_page.dart';
export 'pages/timeline_page.dart';
export 'pages/topics_page.dart';

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
