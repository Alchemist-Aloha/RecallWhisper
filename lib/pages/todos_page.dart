import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../channels.dart';

enum _TodoFilter { all, open, done }

class _TodoItem {
  const _TodoItem({
    required this.id,
    required this.text,
    required this.completed,
    required this.sourceTitle,
  });

  factory _TodoItem.fromMap(Map<Object?, Object?> map) => _TodoItem(
    id: map['id'] as String,
    text: map['text'] as String? ?? '',
    completed: map['completed'] == true,
    sourceTitle: map['sourceTitle'] as String?,
  );

  final String id;
  final String text;
  final bool completed;
  final String? sourceTitle;
}

class TodosPage extends StatefulWidget {
  const TodosPage({super.key});

  @override
  State<TodosPage> createState() => _TodosPageState();
}

class _TodosPageState extends State<TodosPage> {
  List<_TodoItem> todos = const [];
  String? error;
  _TodoFilter filter = _TodoFilter.all;
  int _refreshRequest = 0;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final request = ++_refreshRequest;
    try {
      final values = await nativeCommands.invokeListMethod<Object?>('todos');
      if (!mounted || request != _refreshRequest) return;
      setState(() {
        todos = _fromList(values);
        error = null;
      });
    } on PlatformException catch (exception) {
      if (mounted && request == _refreshRequest) {
        setState(() => error = exception.message);
      }
    }
  }

  Future<void> _toggle(_TodoItem item, bool completed) async {
    try {
      final values = await nativeCommands.invokeListMethod<Object?>(
        'setTodoCompleted',
        <String, Object>{'id': item.id, 'completed': completed},
      );
      if (!mounted) return;
      setState(() => todos = _fromList(values));
    } on PlatformException catch (exception) {
      if (mounted) setState(() => error = exception.message);
    }
  }

  Future<void> _delete(_TodoItem item) async {
    try {
      final values = await nativeCommands.invokeListMethod<Object?>(
        'deleteTodo',
        <String, Object>{'id': item.id},
      );
      if (!mounted) return;
      setState(() => todos = _fromList(values));
    } on PlatformException catch (exception) {
      if (mounted) setState(() => error = exception.message);
    }
  }

  Future<void> _add() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New todo'),
        content: TextFormField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Task'),
          onFieldSubmitted: (value) => Navigator.of(
            context,
          ).pop(value.trim().isEmpty ? null : value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (context, value, _) => FilledButton(
              onPressed: value.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).pop(value.text.trim()),
              child: const Text('Add'),
            ),
          ),
        ],
      ),
    );
    if (text == null || !mounted) return;
    try {
      final values = await nativeCommands.invokeListMethod<Object?>(
        'addTodo',
        <String, Object>{'text': text},
      );
      if (!mounted) return;
      setState(() => todos = _fromList(values));
    } on PlatformException catch (exception) {
      if (mounted) setState(() => error = exception.message);
    }
  }

  Future<void> _extract() async {
    try {
      final added = await nativeCommands.invokeMethod<int>('extractTodos');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              added != null && added > 0
                  ? 'Added $added action item${added == 1 ? '' : 's'}.'
                  : 'No new action items found.',
            ),
          ),
        );
      await refresh();
    } on PlatformException catch (exception) {
      if (mounted) setState(() => error = exception.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = switch (filter) {
      _TodoFilter.all => todos,
      _TodoFilter.open => todos.where((item) => !item.completed).toList(),
      _TodoFilter.done => todos.where((item) => item.completed).toList(),
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('Todos'),
        actions: [
          IconButton(
            tooltip: 'Extract from summaries',
            onPressed: _extract,
            icon: const Icon(Icons.auto_fix_high),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add todo',
        onPressed: _add,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final candidate in _TodoFilter.values)
                  ChoiceChip(
                    label: Text(switch (candidate) {
                      _TodoFilter.all => 'All',
                      _TodoFilter.open => 'Open',
                      _TodoFilter.done => 'Done',
                    }),
                    selected: filter == candidate,
                    onSelected: (_) => setState(() => filter = candidate),
                  ),
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
            if (todos.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 48),
                child: Column(
                  children: [
                    Icon(
                      Icons.checklist,
                      size: 48,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 12),
                    const Text('No todos yet.'),
                    const SizedBox(height: 4),
                    Text(
                      'Extract action items from summaries or add your own.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              )
            else if (visible.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(child: Text('Nothing here.')),
              )
            else
              for (final item in visible)
                Card(
                  child: CheckboxListTile(
                    controlAffinity: ListTileControlAffinity.leading,
                    value: item.completed,
                    onChanged: (completed) => _toggle(item, completed!),
                    title: Text(
                      item.text,
                      style: TextStyle(
                        decoration: item.completed
                            ? TextDecoration.lineThrough
                            : null,
                        color: item.completed
                            ? Theme.of(context).colorScheme.outline
                            : null,
                      ),
                    ),
                    subtitle:
                        item.sourceTitle == null || item.sourceTitle!.isEmpty
                        ? null
                        : Text(
                            'From: ${item.sourceTitle}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                    secondary: IconButton(
                      tooltip: 'Delete',
                      onPressed: () => _delete(item),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  List<_TodoItem> _fromList(List<Object?>? values) => (values ?? const [])
      .map(
        (value) => _TodoItem.fromMap(Map<Object?, Object?>.from(value! as Map)),
      )
      .toList();
}
