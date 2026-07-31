# Repository Guidelines

## Project Structure & Module Organization

RecallWhisper is a Flutter Android app with a native Kotlin recording pipeline. The Flutter UI and platform-channel calls currently live in `lib/main.dart`; widget tests are in `test/widget_test.dart`. Native code is under `android/app/src/main/kotlin/com/recallwhisper/recall_whisper/`, with recording, encryption, Room, WorkManager, playback, and API code in `recording/`. Matching local JVM tests live under `android/app/src/test/kotlin/.../recording/`. Android manifests, resources, and the bundled `silero_vad.onnx` model are under `android/app/src/main/`.

Treat `SPEC.md` section 0 as the authoritative description of the current architecture. The phone is the durable source of truth; transcription and summarization use independently configured OpenAI-compatible APIs.

## Build, Test, and Development Commands

- `flutter pub get` installs Dart dependencies.
- `flutter run` launches the app on a connected Android device or emulator.
- `flutter analyze` runs static analysis with `flutter_lints`.
- `flutter test` runs Flutter widget tests.
- `./android/gradlew -p android testDebugUnitTest` runs native JUnit 4 tests.
- `./android/gradlew -p android testDebugUnitTest assembleDebug` runs native tests and builds the debug APK.
- `dart format lib test` formats Dart sources and tests.

## Coding Style & Naming Conventions

Use two-space indentation for Dart and four spaces for Kotlin. Follow Dart conventions: `lower_snake_case.dart` files, `UpperCamelCase` types and widgets, `lowerCamelCase` members, and `_` prefixes for private declarations. Kotlin files and classes use `UpperCamelCase`; functions and properties use `lowerCamelCase`. Keep native recording code in the existing `com.recallwhisper.recall_whisper.recording` package. Prefer focused changes that reuse existing platform channels, Room entities, and WorkManager scheduling.

## Testing Guidelines

Add Flutter behavior tests with `testWidgets` in `test/widget_test.dart`. Add native logic tests as `*Test.kt` files beside the mirrored package under `android/app/src/test/`. Use mock method-channel handlers for UI/native boundaries. Run both Flutter and Android suites for cross-boundary changes. No coverage threshold is currently defined.

## Commit & Pull Request Guidelines

Recent history uses concise Conventional Commit-style subjects, for example `feat: add data export and transcription features`. Keep commits focused and use an imperative `type: summary` subject. Pull requests should explain the behavior change, list validation commands, link relevant issues, and include screenshots for visible UI changes. Call out changes affecting microphone permissions, encrypted storage, API tokens, HTTP/TLS policy, or local data deletion.
