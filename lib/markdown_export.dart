import 'dart:convert';

import 'format.dart';

String buildSessionsMarkdown(List<Map<Object?, Object?>> sessions) {
  final ordered = [
    ...sessions,
  ]..sort((a, b) => (a['startedAt']! as int).compareTo(b['startedAt']! as int));
  final buffer = StringBuffer();
  for (var index = 0; index < ordered.length; index++) {
    if (index > 0) buffer.write('\n---\n\n');
    buffer.write(_sessionMarkdown(ordered[index]));
  }
  return buffer.toString();
}

String buildSessionsFileName(List<Map<Object?, Object?>> sessions) {
  final days =
      sessions
          .map((session) => _dayKey(session['startedAt']! as int))
          .toSet()
          .toList()
        ..sort();
  final stem = days.length == 1 ? days.single : '${days.first}_to_${days.last}';
  return 'recallwhisper-$stem.md';
}

String _dayKey(int milliseconds) {
  final value = DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

String _sessionMarkdown(Map<Object?, Object?> session) {
  final summary = _parseSummary(session['summary'] as String?);
  final startedAt = session['startedAt']! as int;
  final title =
      _text(summary?['local_title']) ??
      _text(summary?['title']) ??
      'Session ${formatTimestamp(startedAt)}';
  final endedAt = session['endedAt'];
  final buffer = StringBuffer('# $title\n\n');
  buffer.write('Recorded: ${formatTimestamp(startedAt)}');
  if (endedAt is int && endedAt != startedAt) {
    buffer.write(' – ${formatTimestamp(endedAt)}');
  }
  buffer.writeln();
  if (summary == null) {
    final raw = _rawSummary(session['summary'] as String?);
    if (raw != null) buffer.write('\n## Summary\n\n$raw\n');
  } else {
    buffer.write(_summarySections(summary));
  }
  final transcripts = <String>[];
  for (final segment in _segments(session)) {
    final transcript = _text(segment['transcript']);
    if (transcript == null || segment['transcriptionState'] == 'EMPTY') {
      continue;
    }
    transcripts.add(
      '### ${formatTimestamp(segment['startedAt']! as int)}\n\n$transcript\n',
    );
  }
  if (transcripts.isNotEmpty) {
    buffer.write('\n## Transcript\n\n${transcripts.join('\n')}');
  }
  return buffer.toString();
}

String _summarySections(Map<String, dynamic> summary) {
  final buffer = StringBuffer();
  final text = _text(summary['summary']);
  if (text != null) buffer.write('\n## Summary\n\n$text\n');
  final keywords = _stringList([
    summary['keywords'],
    summary['secondary_topics'],
    summary['topics'],
  ]);
  if (keywords.isNotEmpty) {
    buffer.write('\n**Keywords:** ${keywords.join(', ')}\n');
  }
  _appendSection(buffer, 'Decisions', _stringList([summary['decisions']]));
  _appendSection(
    buffer,
    'Action items',
    _stringList([summary['action_items']]),
  );
  _appendSection(buffer, 'Questions', _stringList([summary['questions']]));
  _appendSection(
    buffer,
    'Uncertainties',
    _stringList([summary['uncertainties']]),
  );
  return buffer.toString();
}

void _appendSection(StringBuffer buffer, String title, List<String> values) {
  if (values.isEmpty) return;
  buffer.write('\n### $title\n\n');
  for (final value in values) {
    buffer.writeln('- $value');
  }
}

Map<String, dynamic>? _parseSummary(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  try {
    return jsonDecode(value) as Map<String, dynamic>;
  } on Object {
    return null;
  }
}

String? _rawSummary(String? value) {
  if (_parseSummary(value) != null) return null;
  return _text(value);
}

List<Map<Object?, Object?>> _segments(Map<Object?, Object?> session) {
  final values = session['segments'];
  if (values is List) {
    return values
        .map((value) => Map<Object?, Object?>.from(value! as Map))
        .toList();
  }
  return [session];
}

List<String> _stringList(List<Object?> sources) {
  return [for (final source in sources) ..._strings(source)];
}

List<String> _strings(Object? value) {
  if (value is! List) return const [];
  return value
      .map((item) {
        if (item is Map) {
          return item['text']?.toString() ??
              item['task']?.toString() ??
              item['description']?.toString() ??
              item.toString();
        }
        return item.toString();
      })
      .map((item) => _text(item))
      .whereType<String>()
      .toList();
}

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty || text == 'null' ? null : text;
}
