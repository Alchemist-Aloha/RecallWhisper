import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CopyableText extends StatelessWidget {
  const CopyableText(this.text, {required this.label, this.style, super.key});

  final String text;
  final String label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: SelectableText(text, style: style)),
      IconButton(
        tooltip: 'Copy $label',
        visualDensity: VisualDensity.compact,
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: text));
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('$label copied')));
          }
        },
        icon: const Icon(Icons.copy_outlined),
      ),
    ],
  );
}
