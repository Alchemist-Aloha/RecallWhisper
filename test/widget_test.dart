import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:recall_whisper/main.dart';

void main() {
  testWidgets('shows stopped recorder and empty segment list', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('recall_whisper/recorder'),
          (call) async => call.method == 'status'
              ? <String, Object>{'state': 'STOPPED'}
              : <Object>[],
        );
    await tester.pumpWidget(const RecallWhisperApp());
    await tester.pumpAndSettle();
    expect(find.text('STOPPED'), findsOneWidget);
    expect(find.text('No speech segments yet.'), findsOneWidget);
  });

  testWidgets('debug playground loads models and sends a test', (tester) async {
    var sent = false;
    var healthChecked = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeCommands, (call) async {
          if (call.method == 'debugLoad') {
            return <String, Object>{
              'models': <String>['test-model'],
              'systemPrompt': 'Summarize faithfully.',
            };
          }
          if (call.method == 'debugChat') {
            sent = true;
            return <String, Object>{
              'model': 'test-model',
              'elapsed_ms': 42,
              'output': 'A concise summary.',
            };
          }
          if (call.method == 'debugTranscriptionHealth') {
            healthChecked = true;
            return <String, Object>{
              'healthy': true,
              'elapsed_ms': 20,
              'models': <String>['whisper-test'],
            };
          }
          return null;
        });
    await tester.pumpWidget(const MaterialApp(home: DebugPage()));
    await tester.pumpAndSettle();
    expect(find.text('test-model'), findsWidgets);
    await tester.tap(find.text('Check'));
    await tester.pumpAndSettle();
    expect(healthChecked, isTrue);
    expect(find.textContaining('Healthy · 20 ms'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Test text'),
      'Please summarize this decision.',
    );
    await tester.scrollUntilVisible(
      find.text('Send test request'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Send test request'));
    await tester.pumpAndSettle();
    expect(sent, isTrue);
  });
}
