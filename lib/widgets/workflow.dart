import 'package:flutter/material.dart';

class WorkingIndicator extends SizedBox {
  const WorkingIndicator({super.key})
    : super(
        width: 18,
        height: 18,
        child: const CircularProgressIndicator(strokeWidth: 2),
      );
}

class WorkflowBanner extends StatelessWidget {
  const WorkflowBanner({super.key, required this.activity});

  final ({bool transcribing, bool summarizing}) activity;

  @override
  Widget build(BuildContext context) {
    if (!activity.transcribing && !activity.summarizing) {
      return const SizedBox.shrink();
    }
    final label = activity.transcribing && activity.summarizing
        ? 'Transcription and summary are queued or running'
        : activity.transcribing
        ? 'Transcription is queued or running'
        : 'Summary is queued or running';
    return Semantics(
      liveRegion: true,
      label: label,
      child: Card(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const WorkingIndicator(),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$label…',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
