String formatTimestamp(int milliseconds) {
  final value = DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
  return '${value.year}-${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}:'
      '${value.second.toString().padLeft(2, '0')}';
}

String formatShortTimestamp(int milliseconds) {
  final value = DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
  return '${value.month}/${value.day} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}
