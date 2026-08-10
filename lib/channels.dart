import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const nativeCommands = MethodChannel('recall_whisper/recorder');
final workflowActivity = WorkflowActivity();

class WorkflowActivity
    extends ValueNotifier<({bool transcribing, bool summarizing})> {
  WorkflowActivity() : super((transcribing: false, summarizing: false));

  Timer? _timer;

  Future<void> refresh() async {
    try {
      final status = await nativeCommands.invokeMapMethod<Object?, Object?>(
        'processingStatus',
      );
      final next = (
        transcribing: status?['transcribing'] == true,
        summarizing: status?['summarizing'] == true,
      );
      if (next == value) {
        notifyListeners();
      } else {
        value = next;
      }
      _timer?.cancel();
      if (value.transcribing || value.summarizing) {
        _timer = Timer(const Duration(seconds: 1), refresh);
      }
    } on Object {
      value = (transcribing: false, summarizing: false);
    }
  }

  Future<void> run(String command) async {
    value = (
      transcribing: command == 'transcribeNow' || value.transcribing,
      summarizing: command == 'summarizeNow' || value.summarizing,
    );
    try {
      await nativeCommands.invokeMethod(command);
    } finally {
      await refresh();
    }
  }

  Future<void> stop(String command) async {
    try {
      await nativeCommands.invokeMethod(command);
    } finally {
      await refresh();
    }
  }
}
