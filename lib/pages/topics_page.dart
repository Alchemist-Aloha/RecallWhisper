import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../channels.dart';
import '../format.dart';
import '../widgets/copyable_text.dart';
import '../widgets/workflow.dart';
import 'search_page.dart';
import 'settings_page.dart';

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
                WorkflowBanner(activity: activity),
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
                  '${formatShortTimestamp(topic['firstSeen'] as int)} – '
                  '${formatShortTimestamp(topic['lastSeen'] as int)}',
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CopyableText(
                    topic['description'] as String,
                    label: 'Description',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(height: 1.45),
                  ),
                  if (_isNotEmpty(topic['description']))
                    const SizedBox(height: 16),
                  if (_isNotEmpty(topic['currentSummary'])) ...[
                    Text(
                      'Consolidated summary',
                      style: _sectionHeaderStyle(context),
                    ),
                    const SizedBox(height: 8),
                    CopyableText(
                      topic['currentSummary'] as String,
                      label: 'Consolidated summary',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(height: 1.45),
                    ),
                  ],
                  const Divider(height: 28),
                  if ((topic['episodes'] as List<Object?>? ?? const [])
                      .isNotEmpty) ...[
                    Text('Occurrences', style: _sectionHeaderStyle(context)),
                    const SizedBox(height: 4),
                  ],
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
}

TextStyle? _sectionHeaderStyle(BuildContext context) =>
    Theme.of(context).textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.primary,
    );

bool _isNotEmpty(Object? value) {
  final text = value?.toString().trim();
  return text != null && text.isNotEmpty;
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({required this.episode});

  final Map<Object?, Object?> episode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          CopyableText(
            _episodeSummary(episode['summary'] as String),
            label: 'Episode summary',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
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
