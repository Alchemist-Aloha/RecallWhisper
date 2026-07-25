# RecallWhisper

Android ambient speech capture built with Flutter and a native Kotlin foreground
service. This repository currently implements specification Phase 1 only:

- 16 kHz mono PCM16 `AudioRecord` capture
- bundled Silero VAD v6.2 through ONNX Runtime
- 1.5-second pre-roll, hysteresis, 1.8-second silence timeout
- 180-second WAV segments with 1-second continuation overlap
- atomic finalization, SHA-256, dual wall/monotonic timestamps
- Room segment metadata and a Flutter segment browser
- explicit start, pause, resume, and stop controls

Audio never leaves the phone in this phase. WAV files are private app data and
are not yet encrypted, uploaded, transcribed, or summarized.

## Run

```sh
flutter run
```

Android 7.0 (API 24) or later is required. Start recording while the app is
visible and grant microphone permission. Android keeps a permanent notification
while the microphone service is active.

## Validate

```sh
flutter analyze
flutter test
./android/gradlew -p android testDebugUnitTest assembleDebug
```

The next milestone should begin only after the native recorder passes the
specified eight-hour screen-off test on physical hardware.
