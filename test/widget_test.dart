import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
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
}
