import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:recall_whisper/main.dart';
import 'package:recall_whisper/widgets/copyable_text.dart';

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
    String? clipboardText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
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
    await tester.tap(find.byTooltip('Copy Summary'));
    await tester.pumpAndSettle();
    expect(clipboardText, 'Short summary.');
    expect(find.text('Summary copied'), findsOneWidget);
    expect(find.text('complete'), findsOneWidget);
    expect(find.text('2 segments'), findsOneWidget);
    await tester.tap(find.text('Transcript'));
    await tester.pumpAndSettle();
    expect(find.text('First spoken text.'), findsOneWidget);
    expect(find.text('Second spoken text.'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Copy Transcript').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Copy Transcript').first);
    await tester.pumpAndSettle();
    expect(clipboardText, 'First spoken text.');
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
    final transcriptRetry = find.byTooltip('Retry failed transcripts');
    final summaryRetry = find.byTooltip('Retry failed summaries');
    expect(
      tester.getCenter(find.text('Stop transcript')).dy,
      tester.getCenter(transcriptRetry).dy,
    );
    expect(
      tester.getCenter(find.text('Stop summary')).dy,
      tester.getCenter(summaryRetry).dy,
    );
    expect(
      tester.getCenter(find.text('Stop transcript')).dy,
      lessThan(tester.getCenter(find.text('Stop summary')).dy),
    );
    await tester.tap(find.text('Stop transcript'));
    await tester.pump();
    await tester.tap(find.text('Stop summary'));
    await tester.pumpAndSettle();
    await tester.tap(transcriptRetry);
    await tester.pumpAndSettle();
    await tester.tap(summaryRetry);
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

  testWidgets('summary sections render in order with copyable items', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    String? clipboardText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeCommands, (call) async {
          if (call.method == 'timeline') {
            return <Object>[
              <String, Object?>{
                'id': 'ep_1',
                'isEpisode': true,
                'startedAt': 0,
                'summaryState': 'COMPLETE',
                'summary':
                    '{"summary":"We agreed to ship in phases.",'
                    '"keywords":["alpha","beta"],'
                    '"decisions":["Adopt phased rollout","Keep weekly syncs"],'
                    '"action_items":["Draft migration plan","Assign reviewers"],'
                    '"questions":["Does staging have quota?"],'
                    '"uncertainties":["Estimate may slip two weeks"]}',
                'segments': <Object>[],
              },
            ];
          }
          return null;
        });
    await tester.pumpWidget(const MaterialApp(home: TimelinePage()));
    await tester.pumpAndSettle();

    // The paragraph sits above the emphasized sections, in reading order.
    expect(find.text('We agreed to ship in phases.'), findsOneWidget);
    final paragraph = tester.getTopLeft(
      find.text('We agreed to ship in phases.'),
    );
    final decisions = tester.getTopLeft(find.text('Decisions'));
    final actions = tester.getTopLeft(find.text('Action items'));
    final questions = tester.getTopLeft(find.text('Questions'));
    final uncertainties = tester.getTopLeft(find.text('Uncertainties'));
    expect(paragraph.dy, lessThan(decisions.dy));
    expect(decisions.dy, lessThan(actions.dy));
    expect(actions.dy, lessThan(questions.dy));
    expect(questions.dy, lessThan(uncertainties.dy));

    // Section headers carry an icon and a heavier weight.
    expect(
      tester.widget<Text>(find.text('Decisions')).style?.fontWeight,
      FontWeight.w600,
    );
    expect(find.byIcon(Icons.task_alt), findsOneWidget);

    // Every listed item is individually selectable and copyable.
    expect(find.text('Adopt phased rollout'), findsOneWidget);
    expect(find.text('Estimate may slip two weeks'), findsOneWidget);
    await tester.tap(find.byTooltip('Copy Decision').first);
    await tester.pumpAndSettle();
    expect(clipboardText, 'Adopt phased rollout');
    expect(find.text('Decision copied'), findsOneWidget);
    await tester.tap(find.byTooltip('Copy Uncertainty'));
    await tester.pumpAndSettle();
    expect(clipboardText, 'Estimate may slip two weeks');
    expect(find.text('Uncertainty copied'), findsOneWidget);
  });

  testWidgets(
    'transcript segments lay out on narrow screens without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(360, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeCommands, (call) async {
            if (call.method == 'timeline') {
              return <Object>[
                <String, Object?>{
                  'id': 'ep_1',
                  'isEpisode': true,
                  'startedAt': 0,
                  'summaryState': 'COMPLETE',
                  'summary':
                      '{"summary":"We agreed to ship in phases.",'
                      '"decisions":["Adopt phased rollout"],'
                      '"action_items":["Draft migration plan"],'
                      '"questions":["Does staging have quota?"],'
                      '"uncertainties":["Estimate may slip two weeks"]}',
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
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Transcript'));
      await tester.pumpAndSettle();
      // Episode state plus both segment states render as compact chips.
      expect(find.text('complete'), findsNWidgets(3));
      expect(find.text('First spoken text.'), findsOneWidget);
      expect(find.text('Second spoken text.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('topic content is selectable and sections are labeled', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    String? clipboardText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
    const description =
        'Authentication architecture. Token storage, refresh flows, and '
        'device revocation for the mobile client.';
    const currentSummary =
        'The app now refreshes tokens before they expire and revokes them '
        'when a device is unpaired.';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeCommands, (call) async {
          if (call.method != 'topics') return null;
          return <Object>[
            <String, Object>{
              'id': 'top_1',
              'title': 'Flutter authentication',
              'description': description,
              'currentSummary': currentSummary,
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

    expect(find.text('Consolidated summary'), findsOneWidget);
    expect(find.text('Occurrences'), findsOneWidget);
    expect(find.byTooltip('Copy Description'), findsOneWidget);
    expect(find.byTooltip('Copy Consolidated summary'), findsOneWidget);
    expect(find.byTooltip('Copy Episode summary'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Copy Description'));
    await tester.pumpAndSettle();
    expect(clipboardText, description);
    await tester.tap(find.byTooltip('Copy Episode summary').first);
    await tester.pumpAndSettle();
    expect(clipboardText, 'Moved state out of the widget.');
    expect(tester.takeException(), isNull);
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

  testWidgets('settings stays usable when configuration loading fails', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeCommands, (call) async {
          if (call.method == 'config') {
            throw PlatformException(
              code: 'config_unavailable',
              message: 'Unable to load settings.',
            );
          }
          return null;
        });
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();
    expect(find.text('Transcription server'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('settings uses safe defaults for invalid configuration values', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeCommands, (call) async {
          if (call.method == 'config') {
            return <String, Object?>{
              'cellular': 'true',
              'allowHttp': null,
              'trailingSilenceMs': 1000,
              'episodeGapMinutes': 'invalid',
              'episodeMaxMinutes': 120,
              'transcriptionUrl': 42,
              'transcriptionModel': false,
            };
          }
          return null;
        });
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('5 minutes between recordings'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('5 minutes between recordings'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('60 minutes'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('60 minutes'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('5 seconds before closing a recording'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('5 seconds before closing a recording'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
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

  List<Map<String, Object?>> seededTodos() => <Map<String, Object?>>[
    <String, Object?>{
      'id': 'todo_1',
      'text': 'Send weekly report',
      'completed': true,
      'createdAt': 100,
      'completedAt': 200,
      'sourceEpisodeId': 'ep_1',
      'sourceTitle': 'Weekly sync',
    },
    <String, Object?>{
      'id': 'todo_2',
      'text': 'Draft launch email',
      'completed': false,
      'createdAt': 300,
      'completedAt': null,
      'sourceEpisodeId': null,
      'sourceTitle': null,
    },
  ];

  Future<void> Function(MethodCall) todoStoreMutator(
    List<Map<String, Object?>> store,
    Map<String, Object?> calls,
  ) {
    Future<Object?>? handle(MethodCall call) {
      switch (call.method) {
        case 'todos':
          return Future.value(store);
        case 'addTodo':
          final text = (call.arguments as Map)['text'] as String;
          calls['addTodo'] = text;
          store.insert(0, <String, Object?>{
            'id': 'todo_new',
            'text': text,
            'completed': false,
            'createdAt': 400,
            'completedAt': null,
            'sourceEpisodeId': null,
            'sourceTitle': null,
          });
          return Future.value(store);
        case 'setTodoCompleted':
          final arguments = call.arguments as Map;
          calls['setTodoCompleted'] = Map<String, Object?>.from(arguments);
          for (final todo in store) {
            if (todo['id'] == arguments['id']) {
              todo['completed'] = arguments['completed'] as bool;
            }
          }
          return Future.value(store);
        case 'deleteTodo':
          final id = (call.arguments as Map)['id'] as String;
          calls['deleteTodo'] = id;
          store.removeWhere((todo) => todo['id'] == id);
          return Future.value(store);
        case 'extractTodos':
          calls['extractTodos'] = true;
          return Future.value(2);
      }
      return null;
    }

    return (call) async => await handle(call);
  }

  testWidgets('todos page lists items and toggles completion', (tester) async {
    final store = seededTodos();
    final calls = <String, Object?>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          nativeCommands,
          todoStoreMutator(store, calls),
        );
    await tester.pumpWidget(const MaterialApp(home: TodosPage()));
    await tester.pumpAndSettle();

    expect(find.text('Send weekly report'), findsOneWidget);
    expect(find.text('From: Weekly sync'), findsOneWidget);
    expect(find.text('Draft launch email'), findsOneWidget);

    final openTile = find.widgetWithText(
      CheckboxListTile,
      'Draft launch email',
    );
    Checkbox checkboxOf(Finder tile) => tester.widget<Checkbox>(
      find.descendant(of: tile, matching: find.byType(Checkbox)),
    );
    expect(checkboxOf(openTile).value, isFalse);

    await tester.tap(
      find.descendant(of: openTile, matching: find.byType(Checkbox)),
    );
    await tester.pumpAndSettle();

    expect(calls['setTodoCompleted'], <String, Object?>{
      'id': 'todo_2',
      'completed': true,
    });
    expect(checkboxOf(openTile).value, isTrue);
  });

  testWidgets('todos page survives a failed completion update', (tester) async {
    final store = seededTodos();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeCommands, (call) async {
          if (call.method == 'todos') return store;
          if (call.method == 'setTodoCompleted') {
            throw PlatformException(
              code: 'todo_update_failed',
              message: 'Could not update this todo.',
            );
          }
          return null;
        });
    await tester.pumpWidget(const MaterialApp(home: TodosPage()));
    await tester.pumpAndSettle();

    final checkbox = find.descendant(
      of: find.widgetWithText(CheckboxListTile, 'Draft launch email'),
      matching: find.byType(Checkbox),
    );
    await tester.tap(checkbox);
    await tester.pumpAndSettle();

    expect(find.byType(TodosPage), findsOneWidget);
    expect(find.text('Could not update this todo.'), findsOneWidget);
  });

  testWidgets('todos page adds an item via dialog', (tester) async {
    final store = seededTodos();
    final calls = <String, Object?>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          nativeCommands,
          todoStoreMutator(store, calls),
        );
    await tester.pumpWidget(const MaterialApp(home: TodosPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add todo'));
    await tester.pumpAndSettle();
    final addButton = find.widgetWithText(FilledButton, 'Add');
    expect(
      tester.widget<FilledButton>(addButton).onPressed,
      isNull,
      reason: 'Add must stay disabled while the task text is blank.',
    );

    await tester.enterText(find.byType(TextFormField), 'Ship release notes');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(addButton).onPressed, isNotNull);

    await tester.tap(addButton);
    await tester.pumpAndSettle();

    expect(calls['addTodo'], 'Ship release notes');
    expect(find.text('Ship release notes'), findsOneWidget);
  });

  testWidgets('todos page deletes an item', (tester) async {
    final store = seededTodos();
    final calls = <String, Object?>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          nativeCommands,
          todoStoreMutator(store, calls),
        );
    await tester.pumpWidget(const MaterialApp(home: TodosPage()));
    await tester.pumpAndSettle();

    final doneTile = find.widgetWithText(
      CheckboxListTile,
      'Send weekly report',
    );
    await tester.tap(
      find.descendant(of: doneTile, matching: find.byTooltip('Delete')),
    );
    await tester.pumpAndSettle();

    expect(calls['deleteTodo'], 'todo_1');
    expect(find.text('Send weekly report'), findsNothing);
    expect(find.text('Draft launch email'), findsOneWidget);
  });

  testWidgets('todos page extracts action items from summaries', (
    tester,
  ) async {
    final store = seededTodos();
    final calls = <String, Object?>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          nativeCommands,
          todoStoreMutator(store, calls),
        );
    await tester.pumpWidget(const MaterialApp(home: TodosPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Extract from summaries'));
    await tester.pumpAndSettle();

    expect(calls['extractTodos'], isTrue);
    expect(find.text('Added 2 action items.'), findsOneWidget);
  });

  testWidgets('main shell shows todos tab', (tester) async {
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
          if (call.method == 'todos') return <Object>[];
          return null;
        });
    workflowActivity.value = (transcribing: false, summarizing: false);
    await tester.pumpWidget(const RecallWhisperApp());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Todos'), findsOneWidget);

    await tester.tap(find.text('Todos'));
    await tester.pumpAndSettle();

    expect(find.text('No todos yet.'), findsOneWidget);
    expect(
      find.text('Extract action items from summaries or add your own.'),
      findsOneWidget,
    );
  });

  List<Map<String, Object?>> twoSessionTimeline() => <Map<String, Object?>>[
    <String, Object?>{
      'id': 'ep_2',
      'isEpisode': true,
      'startedAt': 2000,
      'endedAt': 3000,
      'summary':
          '{"local_title":"Second session","summary":"Second summary text.",'
          '"keywords":["alpha"],"action_items":[{"task":"Follow up"}]}',
      'summaryState': 'COMPLETE',
      'segments': <Object>[
        <String, Object?>{
          'id': 'segment-2',
          'startedAt': 2000,
          'transcript': 'Second transcript body.',
          'transcriptionState': 'COMPLETE',
        },
      ],
    },
    <String, Object?>{
      'id': 'ep_1',
      'isEpisode': true,
      'startedAt': 1000,
      'summary': '{"local_title":"First session","summary":"First summary."}',
      'summaryState': 'COMPLETE',
      'segments': <Object>[
        <String, Object?>{
          'id': 'segment-1',
          'startedAt': 1000,
          'transcript': 'First transcript body.',
          'transcriptionState': 'COMPLETE',
        },
      ],
    },
  ];

  void useTallTestSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('long press enters selection and checkboxes toggle sessions', (
    tester,
  ) async {
    useTallTestSurface(tester);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeCommands, (call) async {
          if (call.method == 'timeline') return twoSessionTimeline();
          return null;
        });
    await tester.pumpWidget(const MaterialApp(home: TimelinePage()));
    await tester.pumpAndSettle();

    expect(find.text('Transcripts'), findsOneWidget);
    await tester.longPress(find.text('First session'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(2));
    expect(
      tester
          .widgetList<Checkbox>(find.byType(Checkbox))
          .where((checkbox) => checkbox.value == true)
          .length,
      1,
    );

    await tester.tap(find.text('Second session'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    // Every session is selected, so the app bar toggles to deselect-all.
    expect(find.byTooltip('Deselect all'), findsOneWidget);
    await tester.tap(find.byTooltip('Deselect all'));
    await tester.pumpAndSettle();
    expect(find.text('0 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Select all'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byTooltip('Exit selection'));
    await tester.pumpAndSettle();
    expect(find.text('Transcripts'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byTooltip('Delete transcript'), findsNWidgets(2));
  });

  testWidgets('export selection writes markdown via exportDocument', (
    tester,
  ) async {
    useTallTestSurface(tester);
    Map<Object?, Object?>? exported;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeCommands, (call) async {
          if (call.method == 'timeline') return twoSessionTimeline();
          if (call.method == 'exportDocument') {
            exported = call.arguments as Map<Object?, Object?>;
            return null;
          }
          return null;
        });
    await tester.pumpWidget(const MaterialApp(home: TimelinePage()));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('First session'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Select all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export .md'));
    await tester.pumpAndSettle();

    expect(exported, isNotNull);
    expect(
      exported!['fileName'],
      matches(RegExp(r'^recallwhisper-\d{4}-\d{2}-\d{2}\.md$')),
    );
    expect(exported!['mimeType'], 'text/markdown');
    final content = exported!['content']! as String;
    expect(
      content.indexOf('# First session'),
      lessThan(content.indexOf('# Second session')),
    );
    expect(content, contains('First summary.'));
    expect(content, contains('## Transcript'));
    expect(content, contains('### '));
    expect(content, contains('First transcript body.'));
    expect(content, contains('Second transcript body.'));
    expect(content, contains('- Follow up'));
    expect(content, contains('**Keywords:** alpha'));
    expect(find.text('Markdown export saved'), findsOneWidget);
  });

  testWidgets('delete selection confirms once and removes every session', (
    tester,
  ) async {
    useTallTestSurface(tester);
    final calls = <String>[];
    final deletedIds = <Object?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeCommands, (call) async {
          calls.add(call.method);
          if (call.method == 'timeline') return twoSessionTimeline();
          if (call.method == 'deleteEpisode') {
            deletedIds.add((call.arguments as Map<Object?, Object?>)['id']);
            return null;
          }
          return null;
        });
    await tester.pumpWidget(const MaterialApp(home: TimelinePage()));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('First session'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second session'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete 2 sessions?'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Delete'),
      ),
    );
    await tester.pumpAndSettle();

    expect(deletedIds, containsAll(<Object?>['ep_1', 'ep_2']));
    expect(calls.where((method) => method == 'deleteEpisode'), hasLength(2));
    expect(calls.last, 'timeline');
    expect(find.text('Deleted 2 sessions'), findsOneWidget);
    expect(find.text('2 selected'), findsNothing);
  });

  testWidgets('copy button handles empty, long, repeated and disposed use', (
    tester,
  ) async {
    final copied = <String>[];
    var gate = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
            await gate.future;
          }
          return null;
        });

    // Empty text offers nothing to copy and never writes the clipboard.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CopyableText('', label: 'Empty')),
      ),
    );
    expect(find.byTooltip('Copy Empty'), findsNothing);
    await tester.pump();
    expect(copied, isEmpty);

    // Long selectable content copies exactly and lays out without errors.
    final long = List<String>.filled(300, 'A long spoken paragraph.').join(' ');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CopyableText(long, label: 'Long')),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Copy Long'));
    gate.complete();
    await tester.pumpAndSettle();
    expect(copied.last, long);
    expect(find.text('Long copied'), findsOneWidget);

    // A second tap while the first copy is still pending is ignored.
    copied.clear();
    gate = Completer<void>();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CopyableText('Repeat me', label: 'Repeat')),
      ),
    );
    final copy = find.byTooltip('Copy Repeat');
    await tester.tap(copy);
    await tester.tap(copy);
    gate.complete();
    await tester.pumpAndSettle();
    expect(copied, <String>['Repeat me']);
    expect(find.text('Repeat copied'), findsOneWidget);

    // Unmounting while the clipboard write is still pending is safe.
    copied.clear();
    gate = Completer<void>();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CopyableText('Bye', label: 'Bye')),
      ),
    );
    await tester.tap(find.byTooltip('Copy Bye'));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    gate.complete();
    await tester.pumpAndSettle();
    expect(copied, <String>['Bye']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('single delete reports missing ids and native failures', (
    tester,
  ) async {
    useTallTestSurface(tester);
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeCommands, (call) async {
          calls.add(call.method);
          if (call.method == 'timeline') {
            return <Object>[
              <String, Object?>{
                'startedAt': 0,
                'summary': '{"summary":"Headless session."}',
                'summaryState': 'COMPLETE',
                'transcript': 'Spoken.',
                'transcriptionState': 'COMPLETE',
              },
              <String, Object?>{
                'id': 'gone_1',
                'isEpisode': true,
                'startedAt': 1000,
                'summary': '{"summary":"Gone session."}',
                'segments': <Object>[],
              },
            ];
          }
          if (call.method == 'deleteEpisode') {
            throw PlatformException(
              code: 'not_found',
              message: 'This recording was already deleted.',
            );
          }
          return null;
        });
    await tester.pumpWidget(const MaterialApp(home: TimelinePage()));
    await tester.pumpAndSettle();

    // A row without an id cannot be deleted; it reports clearly instead of crashing.
    final confirmDelete = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Delete'),
    );
    await tester.tap(find.byTooltip('Delete transcript').first);
    await tester.pumpAndSettle();
    await tester.tap(confirmDelete);
    await tester.pumpAndSettle();
    expect(find.textContaining('missing its id'), findsOneWidget);
    expect(calls.where((method) => method == 'deleteEpisode'), isEmpty);

    // A native "already deleted" failure surfaces instead of claiming success.
    await tester.tap(find.byTooltip('Delete transcript').last);
    await tester.pumpAndSettle();
    await tester.tap(confirmDelete);
    await tester.pumpAndSettle();
    expect(calls.where((method) => method == 'deleteEpisode'), hasLength(1));
    expect(find.text('This recording was already deleted.'), findsOneWidget);
    expect(find.textContaining('Deleted'), findsNothing);
  });

  testWidgets('multi-delete reports partial failure and keeps failed item', (
    tester,
  ) async {
    useTallTestSurface(tester);
    final calls = <String>[];
    final deleted = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeCommands, (call) async {
          calls.add(call.method);
          if (call.method == 'timeline') {
            return twoSessionTimeline()
                .where((item) => !deleted.contains(item['id']))
                .toList();
          }
          if (call.method == 'deleteEpisode') {
            final id = (call.arguments as Map)['id'] as String;
            if (id == 'ep_1') {
              throw PlatformException(
                code: 'delete_failed',
                message: 'Storage is busy.',
              );
            }
            deleted.add(id);
          }
          return null;
        });
    await tester.pumpWidget(const MaterialApp(home: TimelinePage()));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Second session'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('First session'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete 2 sessions?'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Delete'),
      ),
    );
    await tester.pumpAndSettle();

    // Both deletes were attempted; the failed one is not claimed as deleted.
    expect(calls.where((method) => method == 'deleteEpisode'), hasLength(2));
    expect(find.textContaining('Deleted 1 of 2 sessions'), findsOneWidget);
    expect(find.text('Storage is busy.'), findsOneWidget);
    expect(find.textContaining('Deleted 2 sessions'), findsNothing);

    // The deleted session is gone, the failed one stays selected for retry.
    expect(find.text('Second session'), findsNothing);
    expect(find.text('First session'), findsOneWidget);
    expect(find.text('1 selected'), findsOneWidget);
    final checkboxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
    expect(checkboxes, hasLength(1));
    expect(checkboxes.single.value, isTrue);
  });
}
