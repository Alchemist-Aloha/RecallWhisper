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

  testWidgets('debug log subpage loads and clears entries', (tester) async {
    var cleared = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeCommands, (call) async {
          if (call.method == 'debugLogs') {
            return '2026-07-31 INFO Recorder started\n';
          }
          if (call.method == 'debugClearLogs') cleared = true;
          return null;
        });
    await tester.pumpWidget(const MaterialApp(home: DebugLogPage()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Recorder started'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear log'));
    await tester.pumpAndSettle();
    expect(cleared, isTrue);
    expect(find.text('No debug events yet.'), findsOneWidget);
  });

  testWidgets('timeline separates transcription and summary states', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeCommands, (call) async {
          if (call.method == 'timeline') {
            return <Object>[
              <String, Object?>{
                'id': 'episode-1',
                'startedAt': 0,
                'summary': '{"summary":"Short summary."}',
                'summaryState': 'COMPLETE',
                'segments': <Object>[
                  <String, Object?>{
                    'id': 'segment-1',
                    'startedAt': 0,
                    'transcript': 'First spoken text.',
                    'transcriptionState': 'COMPLETE',
                  },
                  <String, Object?>{
                    'id': 'segment-2',
                    'startedAt': 1000,
                    'transcript': 'Second spoken text.',
                    'transcriptionState': 'COMPLETE',
                  },
                ],
              },
            ];
          }
          return null;
        });
    await tester.pumpWidget(const MaterialApp(home: TimelinePage()));
    await tester.pumpAndSettle();
    final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    final listView = tester.widget<ListView>(find.byType(ListView));
    expect(scrollbar.thumbVisibility, isTrue);
    expect(scrollbar.interactive, isTrue);
    expect(scrollbar.controller, same(listView.controller));
    expect(find.text('Short summary.'), findsOneWidget);
    expect(find.text('complete'), findsOneWidget);
    expect(find.text('2 segments'), findsOneWidget);
    await tester.tap(find.text('Transcript'));
    await tester.pumpAndSettle();
    expect(find.text('First spoken text.'), findsOneWidget);
    expect(find.text('Second spoken text.'), findsOneWidget);
  });

  testWidgets('timeline does not render an empty summary as content', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeCommands, (call) async {
          if (call.method == 'timeline') {
            return <Object>[
              <String, Object?>{
                'startedAt': 0,
                'transcript': 'Spoken text.',
                'summary': '',
                'transcriptionState': 'COMPLETE',
                'summaryState': 'COMPLETE',
              },
            ];
          }
          return null;
        });
    await tester.pumpWidget(const MaterialApp(home: TimelinePage()));
    await tester.pumpAndSettle();
    expect(find.text('No summary yet.'), findsOneWidget);
  });

  testWidgets('timeline clearly shows an active summary workflow', (
    tester,
  ) async {
    var running = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeCommands, (call) async {
          if (call.method == 'timeline') return <Object>[];
          if (call.method == 'processingStatus') {
            return <String, Object>{
              'transcribing': false,
              'summarizing': running,
            };
          }
          return null;
        });
    workflowActivity.value = (transcribing: false, summarizing: true);
    await tester.pumpWidget(const MaterialApp(home: TimelinePage()));
    await tester.pump();
    expect(find.text('Summary is queued or running…'), findsOneWidget);
    expect(find.text('Stop summary'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Stop summary'),
    );
    expect(button.onPressed, isNotNull);
    running = false;
    await workflowActivity.refresh();
    await tester.pump();
  });

  testWidgets('failed timeline jobs can be manually resubmitted', (
    tester,
  ) async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeCommands, (call) async {
          if (call.method == 'timeline') {
            return <Object>[
              <String, Object?>{
                'id': 'segment-1',
                'startedAt': 0,
                'transcript': null,
                'summary': null,
                'transcriptionState': 'FAILED',
                'summaryState': 'FAILED',
                'transcriptionError': 'Server unavailable.',
                'summaryError': 'Model unavailable.',
              },
            ];
          }
          if (call.method == 'processingStatus') {
            return <String, Object>{
              'transcribing': false,
              'summarizing': false,
            };
          }
          calls.add(call.method);
          return null;
        });
    await tester.pumpWidget(const MaterialApp(home: TimelinePage()));
    await tester.pumpAndSettle();
    expect(find.text('Resubmit summary'), findsOneWidget);
    await tester.tap(find.text('Resubmit summary'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transcript'));
    await tester.pumpAndSettle();
    expect(find.text('Resubmit transcription'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resubmit transcription'));
    await tester.pumpAndSettle();
    expect(calls, containsAll(<String>['retrySummary', 'retryTranscription']));
  });

  testWidgets('transcripts can retry all failed jobs and stop active jobs', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final calls = <String>[];
    var transcribing = true;
    var summarizing = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeCommands, (call) async {
          calls.add(call.method);
          if (call.method == 'timeline') return <Object>[];
          if (call.method == 'stopTranscription') transcribing = false;
          if (call.method == 'stopSummary') summarizing = false;
          if (call.method == 'processingStatus') {
            return <String, Object>{
              'transcribing': transcribing,
              'summarizing': summarizing,
            };
          }
          return 0;
        });
    workflowActivity.value = (transcribing: true, summarizing: true);
    await tester.pumpWidget(const MaterialApp(home: TimelinePage()));
    await tester.pump();
    await tester.tap(find.text('Stop transcript'));
    await tester.pump();
    await tester.tap(find.text('Stop summary'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry transcript'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry summary'));
    await tester.pumpAndSettle();
    expect(
      calls,
      containsAll(<String>[
        'stopTranscription',
        'stopSummary',
        'retryFailedTranscriptions',
        'retryFailedSummaries',
      ]),
    );
  });

  testWidgets('empty transcription has a distinct state and explanation', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeCommands, (call) async {
          if (call.method == 'timeline') {
            return <Object>[
              <String, Object?>{
                'id': 'silent-segment',
                'startedAt': 0,
                'summaryState': 'EMPTY',
                'segments': <Object>[
                  <String, Object?>{
                    'id': 'silent-segment',
                    'startedAt': 0,
                    'transcript': null,
                    'transcriptionState': 'EMPTY',
                  },
                ],
              },
            ];
          }
          return null;
        });
    await tester.pumpWidget(const MaterialApp(home: TimelinePage()));
    await tester.pumpAndSettle();
    expect(find.text('empty'), findsOneWidget);
    await tester.tap(find.text('Transcript'));
    await tester.pumpAndSettle();
    expect(find.text('No human voice detected.'), findsOneWidget);
    expect(find.text('Resubmit transcription'), findsNothing);
  });

  testWidgets('topics keep recurring episodes as separate time ranges', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeCommands, (call) async {
          if (call.method != 'topics') return null;
          return <Object>[
            <String, Object>{
              'id': 'top_1',
              'title': 'Flutter authentication',
              'description': 'Authentication architecture.',
              'currentSummary': 'Current consolidated understanding.',
              'firstSeen': 0,
              'lastSeen': 3600000,
              'episodes': <Object>[
                <String, Object>{
                  'id': 'ep_1',
                  'startedAt': 0,
                  'endedAt': 600000,
                  'title': 'Controller state',
                  'summary': '{"summary":"Moved state out of the widget."}',
                  'status': 'provisional',
                },
                <String, Object>{
                  'id': 'ep_2',
                  'startedAt': 3000000,
                  'endedAt': 3600000,
                  'title': 'Submission handling',
                  'summary': '{"summary":"Prevented duplicate submissions."}',
                  'status': 'provisional',
                },
              ],
            },
          ];
        });
    await tester.pumpWidget(const MaterialApp(home: TopicsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flutter authentication'));
    await tester.pumpAndSettle();
    expect(find.text('Controller state'), findsOneWidget);
    expect(find.text('Submission handling'), findsOneWidget);
    expect(find.text('Moved state out of the widget.'), findsOneWidget);
    expect(find.text('Prevented duplicate submissions.'), findsOneWidget);
  });

  testWidgets('successful equal workflow polls refresh timeline data', (
    tester,
  ) async {
    var timelineCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeCommands, (call) async {
          if (call.method == 'processingStatus') {
            return <String, Object>{
              'transcribing': false,
              'summarizing': false,
            };
          }
          if (call.method == 'timeline') {
            timelineCalls++;
            return <Object>[
              <String, Object?>{
                'startedAt': 0,
                'transcript': 'Transcript $timelineCalls',
                'summaryState': 'WAITING',
                'transcriptionState': 'COMPLETE',
              },
            ];
          }
          return null;
        });
    workflowActivity.value = (transcribing: false, summarizing: false);
    await tester.pumpWidget(const MaterialApp(home: TimelinePage()));
    await tester.pumpAndSettle();
    expect(timelineCalls, 1);
    await workflowActivity.refresh();
    await tester.pumpAndSettle();
    expect(timelineCalls, 2);
    await tester.tap(find.text('Transcript'));
    await tester.pumpAndSettle();
    expect(find.text('Transcript 2'), findsOneWidget);
  });

  testWidgets('successful equal workflow polls refresh topics and banner', (
    tester,
  ) async {
    var topicCalls = 0;
    var summarizing = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeCommands, (call) async {
          if (call.method == 'processingStatus') {
            return <String, Object>{
              'transcribing': false,
              'summarizing': summarizing,
            };
          }
          if (call.method == 'topics') {
            topicCalls++;
            return <Object>[];
          }
          return null;
        });
    workflowActivity.value = (transcribing: false, summarizing: true);
    await tester.pumpWidget(const MaterialApp(home: TopicsPage()));
    await tester.pump();
    expect(find.text('Summary is queued or running…'), findsOneWidget);
    await workflowActivity.refresh();
    await tester.pump();
    expect(topicCalls, 2);
    summarizing = false;
    await workflowActivity.refresh();
    await tester.pump();
  });

  testWidgets('successful equal workflow polls refresh recorder rows', (
    tester,
  ) async {
    var segmentCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeCommands, (call) async {
          if (call.method == 'status') {
            return <String, Object>{'state': 'STOPPED'};
          }
          if (call.method == 'processingStatus') {
            return <String, Object>{
              'transcribing': false,
              'summarizing': false,
            };
          }
          if (call.method == 'segments') {
            segmentCalls++;
            if (segmentCalls == 1) return <Object>[];
            return <Object>[
              <String, Object>{
                'id': 'segment-1',
                'startedAt': 0,
                'durationMs': 1000,
                'sizeBytes': 1024,
                'uploadState': 'COMPLETE',
                'serverState': 'TRANSCRIBED',
              },
            ];
          }
          return null;
        });
    workflowActivity.value = (transcribing: false, summarizing: false);
    await tester.pumpWidget(const MaterialApp(home: RecorderPage()));
    await tester.pumpAndSettle();
    expect(find.text('No speech segments yet.'), findsOneWidget);
    await workflowActivity.refresh();
    await tester.pumpAndSettle();
    expect(segmentCalls, 2);
    expect(find.textContaining('COMPLETE · TRANSCRIBED'), findsOneWidget);
  });

  testWidgets('workflow polls repeat the existing search query', (
    tester,
  ) async {
    var searchCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeCommands, (call) async {
          if (call.method == 'processingStatus') {
            return <String, Object>{
              'transcribing': false,
              'summarizing': false,
            };
          }
          if (call.method == 'search') {
            searchCalls++;
            expect(call.arguments, <String, Object>{'query': 'decision'});
            return <Object>[
              <String, Object>{
                'title': 'Result',
                'excerpt': 'Version $searchCalls',
              },
            ];
          }
          return null;
        });
    workflowActivity.value = (transcribing: false, summarizing: false);
    await tester.pumpWidget(const MaterialApp(home: SearchPage()));
    await tester.enterText(find.byType(SearchBar), 'decision');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Version 1'), findsOneWidget);
    await workflowActivity.refresh();
    await tester.pumpAndSettle();
    expect(searchCalls, 2);
    expect(find.text('Version 2'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    await workflowActivity.refresh();
    await tester.pumpAndSettle();
    expect(searchCalls, 2);
  });

  testWidgets('saving settings starts shared workflow activity', (
    tester,
  ) async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeCommands, (call) async {
          calls.add(call.method);
          if (call.method == 'config') return <String, Object?>{};
          if (call.method == 'processingStatus') {
            return <String, Object>{
              'transcribing': false,
              'summarizing': false,
            };
          }
          return null;
        });
    workflowActivity.value = (transcribing: false, summarizing: false);
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Save'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      calls,
      containsAllInOrder(<String>['saveConfig', 'sync', 'processingStatus']),
    );
  });

  testWidgets('bottom navigation exposes the three primary panels', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeCommands, (call) async {
          if (call.method == 'status') {
            return <String, Object>{'state': 'STOPPED'};
          }
          if (call.method == 'processingStatus') {
            return <String, Object>{
              'transcribing': false,
              'summarizing': false,
            };
          }
          return <Object>[];
        });
    await tester.pumpWidget(const RecallWhisperApp());
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Recorder'), findsOneWidget);
    expect(find.text('Transcripts'), findsOneWidget);
    expect(find.text('Topics'), findsOneWidget);
    await tester.tap(find.text('Transcripts'));
    await tester.pumpAndSettle();
    expect(find.text('Transcripts'), findsWidgets);
  });

  testWidgets('transcript delete requires confirmation and removes episode', (
    tester,
  ) async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeCommands, (call) async {
          calls.add(call.method);
          if (call.method == 'timeline') {
            return <Object>[
              <String, Object?>{
                'id': 'ep_1',
                'isEpisode': true,
                'startedAt': 0,
                'summary': '{"summary":"Short summary."}',
                'summaryState': 'COMPLETE',
                'segments': <Object>[
                  <String, Object?>{
                    'id': 'segment-1',
                    'startedAt': 0,
                    'transcript': 'First spoken text.',
                    'transcriptionState': 'COMPLETE',
                  },
                ],
              },
            ];
          }
          return null;
        });
    await tester.pumpWidget(const MaterialApp(home: TimelinePage()));
    await tester.pumpAndSettle();

    // Cancel leaves the transcript untouched.
    await tester.tap(find.byTooltip('Delete transcript'));
    await tester.pumpAndSettle();
    expect(find.text('Delete transcript?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Delete transcript?'), findsNothing);
    expect(calls.contains('deleteEpisode'), isFalse);

    // Confirming removes the episode and refreshes the timeline.
    await tester.tap(find.byTooltip('Delete transcript'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(calls, containsAllInOrder(<String>['deleteEpisode', 'timeline']));
  });

  testWidgets('recorder transcribe and summarize buttons drive the workflow', (
    tester,
  ) async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeCommands, (call) async {
          calls.add(call.method);
          if (call.method == 'status') {
            return <String, Object>{'state': 'STOPPED'};
          }
          if (call.method == 'processingStatus') {
            return <String, Object>{
              'transcribing': false,
              'summarizing': false,
            };
          }
          return null;
        });
    workflowActivity.value = (transcribing: false, summarizing: false);
    await tester.pumpWidget(const MaterialApp(home: RecorderPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transcribe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Summarize'));
    await tester.pumpAndSettle();
    expect(
      calls,
      containsAllInOrder(<String>['transcribeNow', 'summarizeNow']),
    );
    expect(calls.where((method) => method == 'processingStatus'), hasLength(2));
    expect(workflowActivity.value, (transcribing: false, summarizing: false));
  });

  testWidgets('recorder disables only the active workflow action', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeCommands, (call) async {
          if (call.method == 'status') {
            return <String, Object>{'state': 'STOPPED'};
          }
          if (call.method == 'processingStatus') {
            return <String, Object>{
              'transcribing': false,
              'summarizing': false,
            };
          }
          return null;
        });
    workflowActivity.value = (transcribing: true, summarizing: false);
    await tester.pumpWidget(const MaterialApp(home: RecorderPage()));
    await tester.pump();
    final transcribing = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Transcribing…'),
    );
    expect(transcribing.onPressed, isNull);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Summarize'))
          .onPressed,
      isNotNull,
    );
    workflowActivity.value = (transcribing: false, summarizing: true);
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Summarizing…'))
          .onPressed,
      isNull,
    );
    workflowActivity.value = (transcribing: false, summarizing: false);
  });

  testWidgets('workflow polling stops once status returns idle', (
    tester,
  ) async {
    var statusCalls = 0;
    var active = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeCommands, (call) async {
          if (call.method == 'processingStatus') {
            statusCalls++;
            if (statusCalls >= 3) active = false;
            return <String, Object>{
              'transcribing': active,
              'summarizing': active,
            };
          }
          return null;
        });
    await tester.pumpWidget(const MaterialApp(home: TimelinePage()));
    await tester.pump();
    await workflowActivity.refresh();
    await tester.pump();
    expect(statusCalls, 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(statusCalls, 2);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(statusCalls, 3);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(statusCalls, 3);
  });

  testWidgets('workflow activity resets to idle when status polling fails', (
    tester,
  ) async {
    var failing = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeCommands, (call) async {
          if (call.method == 'processingStatus') {
            if (failing) throw PlatformException(code: 'channel_unavailable');
            return <String, Object>{
              'transcribing': false,
              'summarizing': false,
            };
          }
          return null;
        });
    workflowActivity.value = (transcribing: true, summarizing: false);
    await workflowActivity.refresh();
    expect(workflowActivity.value, (transcribing: false, summarizing: false));
    failing = false;
    await workflowActivity.refresh();
    expect(workflowActivity.value, (transcribing: false, summarizing: false));
  });

  testWidgets('recorder surfaces transcription channel failures', (
    tester,
  ) async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeCommands, (call) async {
          calls.add(call.method);
          if (call.method == 'status') {
            return <String, Object>{'state': 'STOPPED'};
          }
          if (call.method == 'processingStatus') {
            return <String, Object>{
              'transcribing': false,
              'summarizing': false,
            };
          }
          if (call.method == 'transcribeNow') {
            throw PlatformException(
              code: 'work_failed',
              message: 'Server down',
            );
          }
          return null;
        });
    workflowActivity.value = (transcribing: false, summarizing: false);
    await tester.pumpWidget(const MaterialApp(home: RecorderPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transcribe'));
    await tester.pumpAndSettle();
    expect(find.text('Server down'), findsOneWidget);
    expect(
      calls,
      containsAllInOrder(<String>['transcribeNow', 'processingStatus']),
    );
    expect(workflowActivity.value, (transcribing: false, summarizing: false));
  });

  testWidgets('retry actions pass the exact episode and segment ids', (
    tester,
  ) async {
    final arguments = <String, Object?>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeCommands, (call) async {
          if (call.method == 'timeline') {
            return <Object>[
              <String, Object?>{
                'id': 'ep_1',
                'isEpisode': true,
                'startedAt': 0,
                'transcript': null,
                'summary': null,
                'transcriptionState': 'FAILED',
                'summaryState': 'FAILED',
                'segments': <Object>[
                  <String, Object?>{
                    'id': 'segment-1',
                    'startedAt': 0,
                    'transcript': null,
                    'transcriptionState': 'FAILED',
                  },
                ],
              },
            ];
          }
          if (call.method == 'processingStatus') {
            return <String, Object>{
              'transcribing': false,
              'summarizing': false,
            };
          }
          if (call.method == 'retrySummary' ||
              call.method == 'retryTranscription') {
            arguments[call.method] = call.arguments;
          }
          return null;
        });
    workflowActivity.value = (transcribing: false, summarizing: false);
    await tester.pumpWidget(const MaterialApp(home: TimelinePage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resubmit summary'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transcript'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resubmit transcription'));
    await tester.pumpAndSettle();
    expect(arguments['retrySummary'], <String, Object>{'id': 'ep_1'});
    expect(arguments['retryTranscription'], <String, Object>{
      'id': 'segment-1',
    });
  });
}
