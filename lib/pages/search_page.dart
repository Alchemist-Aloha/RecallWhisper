import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../channels.dart';

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
