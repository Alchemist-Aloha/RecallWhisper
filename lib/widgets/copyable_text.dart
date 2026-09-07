import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CopyableText extends StatefulWidget {
  const CopyableText(this.text, {required this.label, this.style, super.key});

  final String text;
  final String label;
  final TextStyle? style;

  @override
  State<CopyableText> createState() => _CopyableTextState();
}

class _CopyableTextState extends State<CopyableText> {
  bool _copying = false;

  @override
  Widget build(BuildContext context) {
    final text = widget.text.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: SelectableText(widget.text, style: widget.style)),
        // Nothing useful to copy; keep the layout stable without a dead button.
        if (text.isEmpty)
          const SizedBox.shrink()
        else
          IconButton(
            tooltip: 'Copy ${widget.label}',
            visualDensity: VisualDensity.compact,
            onPressed: _copying ? null : _copy,
            icon: const Icon(Icons.copy_outlined),
          ),
      ],
    );
  }

  Future<void> _copy() async {
    if (_copying) return;
    setState(() => _copying = true);
    try {
      await Clipboard.setData(ClipboardData(text: widget.text));
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('${widget.label} copied')));
    } on PlatformException {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Could not copy ${widget.label}')),
        );
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }
}
