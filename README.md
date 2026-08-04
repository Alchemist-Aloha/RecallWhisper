# RecallWhisper

Private Android ambient capture with all durable data stored on the phone.

## Data flow

```text
Microphone → encrypted local WAV → transcription API
           → local raw transcript → summarization API
           → local summary/search/export
```

- Native Kotlin foreground service and Quick Settings tile
- Silero VAD with configurable 5–60 second conversation pause tolerance
- Per-file AES-256-GCM keys wrapped by Android Keystore
- Room metadata, raw transcription responses, transcripts, and summaries
- Direct OpenAI-compatible transcription and summarization endpoints
- Wi-Fi-only processing by default; cellular is opt-in
- Local playback, transcript search, deletion, API playground, and JSON export

## Configure

In Settings, configure the transcription and summarization URL, token, and
model separately. HTTPS is required unless “Allow insecure HTTP” is explicitly
enabled for a trusted development network.

Settings → Debug and API playground can list summarization models, edit the
local system prompt, send arbitrary text, tune generation parameters, and
inspect response latency and errors. It also includes an authenticated
transcription-server health and model-discovery check.

“Export all data as JSON” opens Android’s document picker and writes segment
metadata, raw transcription results, transcripts, summaries, processing state,
and checksums to a user-selected file. Audio remains separately encrypted in
private app storage.

## Build

```sh
flutter analyze
flutter test
./android/gradlew -p android testDebugUnitTest assembleDebug
```
