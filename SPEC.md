# Personal Ambient Recorder and Recall System

> **Implementation amendment (2026-07-25):** The original architecture below
> remains the design baseline, but the current application intentionally differs
> from it as recorded in section 0. There is no RecallWhisper backend service.
>
> **Status review (2026-07-31):** Section 0 was re-verified line by line against
> the source tree. It accurately describes the implemented application; the
> provider-specific chat extensions and the cleartext-traffic manifest flag are
> now additionally recorded in sections 0.3 and 0.4.

**Specification version:** 1.1  
**Target platform:** Android application built with Flutter and a native Kotlin recording engine  
**Processing model:** Self-hosted dedicated ASR plus an OpenAI-compatible text LLM  
**Primary use case:** Continuous, user-controlled ambient speech capture, transcription, organization, summarization, and future recall

---

# 0. Current implementation and deviations

This section is authoritative for the current application. Requirements in
later sections that conflict with this section describe the original baseline
or future work and are not implemented requirements.

## 0.1 Current data flow

```text
Android microphone
        ↓
Continuous native Silero VAD
        ↓
Encrypted WAV speech segments in private app storage
        ↓
WorkManager processing queue
        ↓
Configured OpenAI-compatible transcription API
        ↓
Raw response and transcript stored in Room
        ↓
Configured OpenAI-compatible summarization API
        ↓
Contiguous timestamped topic episode
        ↓
Episode summary linked to a stable canonical topic
        ↓
Local segment timeline, topic timeline, text search, playback, deletion, and JSON export
```

The phone is the authoritative durable store. RecallWhisper does not upload to,
depend on, or synchronize with a RecallWhisper-owned server.

## 0.2 Deviation register

| Original baseline | Current implementation |
|---|---|
| A RecallWhisper ingestion server permanently stores and processes uploaded data. | The ingestion server has been removed. The phone stores segment metadata, encrypted audio, raw transcription responses, transcripts, summaries, processing errors, and checksums. |
| One server URL and authentication path handle synchronization. | Transcription and summarization have independent base URLs, bearer tokens, and model names. Tokens are encrypted with an Android Keystore-backed key. |
| The server runs `faster-whisper`. | RecallWhisper calls any configured OpenAI-compatible `POST /v1/audio/transcriptions` endpoint. The ASR implementation and model hosting are external to the app. |
| The server owns the text LLM pipeline. | RecallWhisper directly calls a separately configured OpenAI-compatible `POST /v1/chat/completions` endpoint. |
| Segments are uploaded in batches to an idempotent ingestion API. | WorkManager processes locally queued segments individually. It decrypts each segment in memory, transcribes it, optionally summarizes it, and stores the results locally. Wi-Fi/unmetered networking is the default; cellular is opt-in. |
| Upload/server processing states describe remote ingestion jobs. | The existing `uploadState` and `serverState` fields are retained as legacy names for local API-processing state. There is no RecallWhisper server state to synchronize. |
| Ogg Opus is the normal stored format, with AAC fallback. | The current recorder writes PCM16 WAV and then encrypts it as `.wav.enc`. Opus/AAC encoding is not implemented. |
| The default trailing-silence timeout is 1.8 seconds. | Conversation pause tolerance is user-configurable from 5–60 seconds and defaults to 30 seconds. This intentionally keeps nearby speech in a continuous recording. |
| Separate Room entities track configuration, upload attempts, server status, tombstones, and device events. | A single `capture_segment` entity currently holds capture, encryption, processing, transcript, summary, and error fields. Configuration is stored in encrypted/shared preferences where appropriate. |
| Summarization occurs after conversation reconstruction and normalization. | Successfully transcribed capture segments are grouped into provisional contiguous topic episodes using boot/session, inactivity-gap, and maximum-duration boundaries. Each closed group is summarized once and linked to a stable canonical topic. Semantic embeddings, offline reconciliation, transcript normalization, and manual merge/split controls remain future work. |
| Summary JSON is schema-validated and every extracted claim must carry evidence spans. | The app requests JSON output using an editable system prompt, but currently performs no JSON-schema, evidence-span, or timestamp-range validation. |
| Search combines full-text indexing, embeddings, filters, and evidence-backed recall. | Search is local SQL substring matching over transcript and summary text. There is no FTS index, vector index, semantic retrieval, or generated recall answer. |
| Audio playback links can begin at an evidence timestamp. | The timeline can decrypt and play or stop an entire local recording. Seeking to an evidence timestamp is not implemented. |
| Export and deletion cover synchronized phone and server data. | Segment deletion removes the local encrypted audio and Room row only. JSON export uses Android's document picker and exports local metadata and derived text; encrypted audio files are not embedded in the JSON. |
| Retention workers remove local audio after successful transcription and apply server retention policies. | No automatic retention or pruning policy is implemented. Audio remains on the phone until the user deletes it or application data is removed. |
| Recovery finalizes recoverable temporary recordings and records diagnostic events. | Startup renames unfinished `.wav.tmp` files as corrupt. It does not reconstruct them or persist a recovery-event record. |
| The notification includes pause/resume, save-recent, open, and stop actions. | The notification provides open, pause/resume, and stop. Save-recent is not implemented. A Quick Settings recorder tile is implemented. |
| HTTPS is always required for remote APIs. | HTTPS remains the default. A user-controlled “Allow insecure HTTP” setting permits plain HTTP for trusted development networks. It does not disable HTTPS certificate validation. |
| Server observability and extensive device metrics are collected. | The app exposes processing state/errors and a debug API playground, but does not implement the complete metrics sets in section 27. |

## 0.3 Added current features

The following features were added beyond the original phased implementation:

- Local encrypted playback from the recording timeline.
- Local deletion of individual recordings.
- User-selected JSON export through Android storage access.
- Separate transcription and summarization endpoint configuration.
- Separate encrypted bearer tokens and model selections for both APIs.
- Editable summarization system prompt.
- Summarization API playground with model discovery, arbitrary input text,
  JSON-mode selection, temperature, top-p, token limit, frequency penalty,
  presence penalty, latency, output, and error inspection.
- Transcription server connectivity/model check using its authenticated
  `/v1/models` endpoint.
- Explicit opt-in for insecure HTTP API URLs.
- Provisional topic episodes with configurable inactivity and duration limits.
- Stable opaque canonical-topic IDs that link recurring, noncontiguous episodes.
- A topic-centered timeline that preserves each episode's original time range.
- A configurable summary language. The default follows the transcript's primary
  language; users may specify a language such as English or Simplified Chinese.
- Word-level timestamps are requested from the transcription API
  (`response_format=verbose_json` with `timestamp_granularities[]=word`) and the
  raw response is preserved, but the timestamps are not yet used for evidence
  linking or seek playback.
- The summarization chat request carries provider-specific extensions — a
  `chat_template_kwargs.enable_thinking = false` block and a `/no_think` suffix
  on the user message — targeting reasoning-capable OpenAI-compatible servers
  that support them.

## 0.6 Continuous-transcript organization and summary contract

RecallWhisper shall not treat continuous capture as one endless document and
shall not maintain one destructive rolling summary. The implemented summary
pipeline is:

```text
immutable timestamped capture segments
        ↓
provisional contiguous topic episodes
        ↓
one structured summary per episode
        ↓
canonical topic matching/linking
        ↓
topic-centered timeline of separate occurrences
```

An **episode** is one contiguous occurrence. A **canonical topic** is a stable
persistent subject that may recur across many noncontiguous episodes. Separate
occurrences must never be collapsed into one timestamp range.

The phone retains the original ASR transcript and raw ASR response on each
capture segment. Episode processing references segments rather than copying or
replacing their source text. Topic and episode IDs are opaque and stable;
model-generated titles may change without becoming database identities.

The current online episode boundary rules are deliberately deterministic:

- a device boot boundary always starts a new episode;
- an inactivity gap starts a new episode (default 5 minutes, configurable
  3–10 minutes);
- the maximum episode duration closes an episode (default 30 minutes,
  configurable 10–60 minutes).

The summarization model receives timestamped text for the whole episode and a
bounded list of existing canonical topics. It must return strict JSON containing
the local episode title, episode summary, primary canonical topic, hierarchy
path, secondary topic tags, keywords, decisions, actions, questions, and
uncertainties. A returned canonical topic ID is accepted only when it exactly
matches an ID supplied by the app; otherwise the app creates a new opaque ID.
All natural-language output fields must use the configured summary language.

Topic-specific state is append-oriented. Every episode summary remains stored
separately, while the canonical topic stores a replaceable cumulative summary
for browsing. The episode records are the historical source of truth.

The following supplied best-practice stages remain explicit future work:

- 30–90 second overlapping analysis windows independent of audio file size;
- embeddings and combined semantic, lexical, speaker, and discourse scoring;
- ambiguous-boundary classification and gradual-drift detection;
- parenthetical-event and important micro-episode handling;
- offline hourly reconciliation of provisional boundaries;
- duplicate-topic merge proposals with aliases/redirects;
- hourly and daily summaries generated from episode summaries;
- evidence-span validation and timestamp-seek playback.

## 0.4 TLS and OpenASR compatibility boundary

The current HTTP client uses Android's standard TLS trust validation and
standard OpenAI bearer authentication. It does not implement:

- Trust-on-first-use or certificate fingerprint pinning.
- Trust of arbitrary self-signed certificates.
- OpenASR pairing request, approval, or credential retrieval.
- The OpenASR `x-openasr-remote-compute: client` authentication flow.

An OpenASR server using `--tls-self-signed` therefore requires a trusted HTTPS
reverse proxy, a certificate trusted by Android, or future client-side
certificate-pinning and pairing support. Enabling insecure HTTP does not make a
self-signed HTTPS certificate trusted.

The application manifest declares `android:usesCleartextTraffic="true"` to
support the development-network setting; each API request independently enforces
the HTTPS scheme in `NetworkPolicy`, which rejects plain HTTP unless the
"Allow insecure HTTP" preference is enabled.

## 0.5 Remaining baseline work

The following major baseline capabilities remain future work:

- Opus/AAC encoding and codec negotiation.
- Recoverable atomic-finalization workflow and richer crash diagnostics.
- Automatic retention controls and date-range deletion.
- Semantic episode-boundary reconciliation and user merge/split controls.
- Transcript normalization and transcript correction.
- Structured evidence validation, hourly/daily digests, and summary versioning.
- Diarization, speaker naming, and voice enrollment.
- Full-text indexing, embeddings, hybrid recall, and memory promotion.
- Evidence-linked transcript navigation and timestamped playback.
- The soak, battery, device-matrix, and recorded-corpus validation described in
  section 28.

---

## 1. Executive design decision

The system shall use this pipeline:

```text
Android microphone
        ↓
Continuous low-cost on-device VAD
        ↓
Timestamped speech segments
        ↓
Encrypted local queue
        ↓
Batched transfer to self-hosted server
        ↓
Dedicated ASR using faster-whisper
        ↓
Timestamped transcript
        ↓
Conversation reconstruction and optional diarization
        ↓
Text LLM summarization and structured extraction
        ↓
Full-text + semantic search
        ↓
Recall interface with evidence links
```

The following design decisions are central:

1. **Flutter handles the user interface, configuration, history view, and coarse service control.**
2. **A native Kotlin foreground service handles the microphone, VAD, buffering, encoding, and crash recovery.**
3. **The microphone stream remains open while ambient recording is enabled.**
4. **Silence is processed in memory but not normally written to storage.**
5. **Every audio segment receives authoritative capture timestamps on the phone.**
6. **The server produces and permanently stores a transcript before summarization.**
7. **Summaries and memories must reference supporting transcript spans.**
8. **Audio, transcript, summary, and long-term memory are separate data layers.**
9. **Uploads are batched operationally, but each audio segment remains independently identifiable and retryable.**
10. **The system must remain useful even if the summarization model is replaced later.**

---

# 2. Goals

The system should:

- Operate for extended periods with the screen off.
- Detect and preserve ordinary conversational speech.
- Avoid writing hours of silence.
- Preserve the beginning and end of speech.
- Associate every recording and transcript with reliable absolute timestamps.
- Survive application crashes, server outages, network loss, and device restarts.
- Support delayed transcription when the server is unavailable.
- Produce searchable transcripts.
- Group nearby recordings into meaningful conversations.
- Generate structured summaries, decisions, tasks, topics, people, and memory candidates.
- Permit every generated claim to be traced back to the transcript and preferably the original audio.
- Allow retranscription and resummarization using improved models.
- Minimize unnecessary battery, storage, and network use.
- Encrypt sensitive data locally and in transit.
- Give the user obvious pause, deletion, and retention controls.

---

# 3. Non-goals for the initial release

Version 1 should not attempt to:

- Identify every person by voice.
- Infer emotions as factual statements.
- Record telephone calls.
- bypass Android microphone indicators or foreground-service requirements.
- Automatically resume microphone recording invisibly after reboot.
- Create permanent personal memories from every casual statement.
- Guarantee forensic-quality word timing.
- Run Whisper or a large language model on the phone.
- Replace the original transcript with an LLM-corrected version.
- Continuously upload every utterance immediately.

Android requires microphone foreground-service declarations for applicable target versions, and modern Android restricts launching microphone foreground services from the background or from `BOOT_COMPLETED`. The product should therefore expect the user to explicitly resume ambient recording after a reboot. 

---

# 4. System components

## 4.1 Android application

The Android application consists of:

```text
Flutter layer
├── Settings
├── Recorder status
├── Timeline
├── Transcript viewer
├── Search and recall UI
├── Upload status
├── Privacy controls
└── Native-service command interface

Native Kotlin layer
├── RecorderForegroundService
├── AudioCaptureEngine
├── VadEngine
├── SpeechSegmenter
├── AudioEncoder
├── LocalMetadataStore
├── EncryptionManager
├── UploadScheduler
└── RecoveryManager
```

## 4.2 Self-hosted server

```text
API gateway
├── Authentication
├── Upload negotiation
├── Segment ingestion
└── Query API

Processing services
├── Audio validation
├── ASR worker
├── Sessionizer
├── Optional diarization worker
├── Summarization worker
├── Embedding worker
└── Retention worker

Storage
├── Object/audio storage
├── Relational database
├── Full-text index
├── Vector index
└── Job queue
```

A single-machine deployment may initially run all server components through Docker Compose.

---

# 5. Android recording architecture

## 5.1 Foreground service

Recording shall run in a native Android foreground service declared with:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission
    android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

<service
    android:name=".recording.RecorderForegroundService"
    android:exported="false"
    android:foregroundServiceType="microphone" />
```

The service notification should provide:

- Current state: listening, recording, paused, or error.
- A pause/resume action.
- A “save recent moment” action if a rolling buffer is offered.
- An application-open action.
- A stop action.

The foreground service should be started while the application is visible and after microphone permission has been granted.

## 5.2 Flutter/native boundary

Flutter shall not receive every PCM frame.

Communication should be limited to coarse commands:

```dart
startAmbientRecording()
pauseAmbientRecording()
resumeAmbientRecording()
stopAmbientRecording()
getRecorderStatus()
updateRecorderConfiguration()
```

Native-to-Flutter events should include:

```dart
sealed class RecorderEvent {}

class StateChanged extends RecorderEvent {
  final RecorderState state;
}

class SegmentCompleted extends RecorderEvent {
  final String segmentId;
  final Duration duration;
}

class UploadQueueChanged extends RecorderEvent {
  final int pendingCount;
}

class RecorderError extends RecorderEvent {
  final String code;
  final String message;
}
```

Passing 20–32 ms audio frames through platform channels would create unnecessary allocations, Dart wakeups, and serialization overhead.

---

# 6. Audio capture specification

## 6.1 Default capture format

| Parameter | Default |
|---|---:|
| Sample rate | 16,000 Hz |
| Channels | Mono |
| Sample representation | Signed PCM16 |
| Bytes per sample | 2 |
| VAD frame length | 512 samples |
| VAD frame duration | 32 ms |
| Audio source | `VOICE_RECOGNITION` |
| Fallback audio source | `MIC` |

Android supports PCM16 broadly, and 16 kHz is appropriate for speech recognition. Silero’s current VAD uses fixed 512-sample windows at 16 kHz. 

`VOICE_RECOGNITION` should be tested first because Android documentation recommends it where unwanted automatic gain control or noise suppression is a concern. OEM behavior varies, so `MIC` and `UNPROCESSED` should remain testable alternatives. 

## 6.2 AudioRecord initialization

Conceptual Kotlin configuration:

```kotlin
private const val SAMPLE_RATE = 16_000

val format = AudioFormat.Builder()
    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
    .setSampleRate(SAMPLE_RATE)
    .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
    .build()

val minimumBuffer = AudioRecord.getMinBufferSize(
    SAMPLE_RATE,
    AudioFormat.CHANNEL_IN_MONO,
    AudioFormat.ENCODING_PCM_16BIT
)

val recorder = AudioRecord.Builder()
    .setAudioSource(MediaRecorder.AudioSource.VOICE_RECOGNITION)
    .setAudioFormat(format)
    .setBufferSizeInBytes(maxOf(minimumBuffer * 4, 16_384))
    .build()
```

The capture thread should:

- Use a dedicated native thread.
- Reuse buffers.
- Avoid per-frame object allocation.
- Detect partial reads and audio errors.
- Keep a monotonically increasing sample counter.
- Avoid updating the UI for each frame.
- Avoid writing to the database for each frame.

## 6.3 Read granularity

The system should read approximately 128–256 ms per `AudioRecord.read()` call and divide that buffer internally into 32 ms VAD frames.

For example:

```text
AudioRecord read:
    4096 samples = 256 ms at 16 kHz

VAD processing:
    8 × 512-sample frames
```

This reduces thread wakeups without reducing VAD temporal resolution.

---

# 7. Voice activity detection

## 7.1 Recommended VAD

Use the current **Silero VAD ONNX model** as the default.

Reasons:

- Small model footprint.
- CPU inference suitable for edge use.
- Probability output instead of only a binary flag.
- Good robustness under changing noise conditions.
- Fixed and predictable 32 ms input at 16 kHz.

Silero reports sub-millisecond processing for short chunks on a CPU thread under its test conditions and a model size of approximately 2 MB. These figures should still be validated on the actual target phone. 

A WebRTC VAD backend may be added later as a lower-compute alternative.

## 7.2 Do not use heartbeat sampling

The system shall not periodically open the microphone, listen briefly, and close it.

A periodic heartbeat such as:

```text
record 250 ms
sleep 750 ms
repeat
```

can miss speech that occurs during the sleep interval and can clip the beginning of an utterance. It also repeatedly initializes the audio route.

Instead:

```text
Microphone continuously open
        ↓
VAD continuously evaluates frames
        ↓
Only confirmed speech is persisted
```

## 7.3 Ring buffer

Maintain a PCM ring buffer containing the most recent **1.5 seconds**:

```text
16,000 samples/s × 1.5 s × 2 bytes
= 48,000 bytes
```

The ring buffer should run continuously while listening.

When speech is confirmed:

1. Open a new segment.
2. Copy the ring buffer into the segment.
3. Append subsequent audio.
4. Continue until the end-of-speech rule is satisfied.

This protects the first syllable from VAD confirmation delay.

## 7.4 VAD thresholds

Recommended starting values:

| Setting | Initial value |
|---|---:|
| Speech-start probability | 0.60 |
| Speech-continuation probability | 0.35 |
| Start decision | 3 positive frames among 5 |
| Minimum real speech | 350 ms |
| Pre-roll | 1.5 s |
| Trailing-silence timeout | 1.8 s |
| Post-roll | 400 ms |
| Maximum continuous segment | 180 s |
| Split overlap | 1.0 s |

The two probability thresholds provide hysteresis:

```text
Not recording:
    require probability ≥ 0.60

Already recording:
    treat probability ≥ 0.35 as possible speech
```

This avoids rapid switching near one threshold.

## 7.5 Recorder state machine

```text
STOPPED
   │ start
   ▼
LISTENING
   │ probable speech
   ▼
POSSIBLE_SPEECH
   │ confirmation reached
   ▼
RECORDING
   │ sustained non-speech
   ▼
TRAILING_SILENCE
   ├── speech resumes ───────────────► RECORDING
   └── timeout reached
                  ▼
              FINALIZING
                  ▼
              LISTENING
```

State behavior:

### `LISTENING`

- Microphone is open.
- VAD is active.
- Ring buffer is updated.
- No file is being written.

### `POSSIBLE_SPEECH`

- Positive-frame history is evaluated.
- Ring buffer continues.
- If speech is not confirmed, return to `LISTENING`.

### `RECORDING`

- Ring buffer is flushed once.
- PCM is passed to the encoder.
- Segment metadata is initialized.
- VAD continues to run.

### `TRAILING_SILENCE`

- Audio continues to be encoded temporarily.
- Speech can return without opening a new segment.
- Segment closes after the silence timeout.

### `FINALIZING`

- Encoder is drained.
- Output is closed.
- Checksum is calculated.
- Metadata is committed.
- Upload work is scheduled.

## 7.6 False-trigger handling

A segment should be classified as a VAD misfire when:

- Confirmed speech duration is under 350 ms.
- The audio contains only a transient click or impact.
- The server’s ASR returns no usable speech.
- No-speech confidence is high.

Misfires may be deleted immediately or retained briefly for VAD tuning, depending on diagnostic settings.

---

# 8. Segment boundaries and file strategy

## 8.1 Keep capture segments independent

Each speech event should normally become one independently identifiable audio object.

Do not concatenate unrelated utterances into one audio file after deleting long silences unless a precise audio-to-wall-clock mapping is also stored.

Preferred behavior:

```text
Speech event A → segment A
8 seconds silence
Speech event B → segment B
```

The sessionizer can later determine that A and B belong to the same conversation.

## 8.2 Maximum duration

A continuously voiced segment should be split at **180 seconds** with a **1-second overlap**.

Reasons:

- Limits recovery loss if a file is corrupted.
- Keeps retries small.
- Prevents extremely large ASR jobs.
- Limits encoder and memory state.
- Still provides sufficient transcription context.

Metadata shall mark the relationship:

```json
{
  "continuation_group_id": "01J4...",
  "continuation_index": 2,
  "overlap_ms": 1000
}
```

The server should remove duplicated transcript text caused by the overlap.

---

# 9. Audio encoding

## 9.1 Preferred codec

Use:

```text
Preferred:
    Ogg Opus, mono, 16 kHz, 24 kbps variable bitrate

Fallback:
    AAC-LC in M4A, mono, 16 or 32 kHz, 32 kbps
```

Android lists Opus encoding support from Android 10 onward and decoding support from Android 5.0 onward. Current Media3 also provides an Ogg muxer for Opus. 

The application should query codec availability rather than assuming support.

## 9.2 Development fallback

During early development, use WAV PCM16 because it simplifies debugging:

```text
WAV:
    simple and lossless
    approximately 115 MB per recorded hour

Opus at 24 kbps:
    approximately 10.8 MB per recorded hour
```

WAV should not be the default long-term format.

## 9.3 Atomic file creation

The application shall write:

```text
<segment-id>.audio.tmp
```

After the encoder closes successfully:

1. Flush output.
2. Close the stream.
3. Compute SHA-256.
4. Persist metadata in a transaction.
5. Rename atomically to:

```text
<segment-id>.opus.enc
```

A completed filename must never refer to a partially written file.

---

# 10. Timestamp model

## 10.1 Use two time bases

For every segment, store:

1. **UTC wall-clock time**
2. **Monotonic elapsed-realtime time**

Android’s wall clock can jump because of user changes, network synchronization, time-zone changes, or daylight-saving changes. `elapsedRealtimeNanos()` is monotonic and includes time spent in deep sleep. 

At segment start, capture:

```kotlin
val wallStartMs = System.currentTimeMillis()
val elapsedStartNs = SystemClock.elapsedRealtimeNanos()
```

## 10.2 Required capture metadata

```json
{
  "segment_id": "019c94c7-4adc-7f74-8747-2be749f92c22",
  "device_id": "phone-01",
  "boot_id": "2cadc41c-...",
  "sequence_number": 28412,

  "started_at_utc": "2026-07-25T01:42:13.482Z",
  "ended_at_utc": "2026-07-25T01:42:42.901Z",

  "timezone_name": "America/New_York",
  "utc_offset_minutes": -240,

  "elapsed_start_ns": 8942315228194,
  "elapsed_end_ns": 8971734228194,

  "sample_rate_hz": 16000,
  "channels": 1,
  "sample_count": 470704,
  "duration_ms": 29419,

  "codec": "opus",
  "container": "ogg",
  "bitrate_bps": 24000,

  "pre_roll_ms": 1500,
  "post_roll_ms": 400,
  "vad_model": "silero",
  "vad_configuration_version": 1,

  "sha256_ciphertext": "...",
  "encryption_version": 1
}
```

## 10.3 Timestamp authority

The phone’s segment start time is authoritative.

The ASR server should return relative offsets:

```json
{
  "start_ms": 5320,
  "end_ms": 7810,
  "text": "We should repeat that measurement tomorrow."
}
```

Absolute time is calculated as:

```text
segment.started_at_utc + ASR relative offset
```

Word timestamps from Whisper should be treated as approximate navigational timestamps, not forensic timing.

---

# 11. Local metadata database

Use Room on Android.

Recommended entities:

```text
RecorderConfiguration
CaptureSegment
UploadAttempt
ServerProcessingStatus
DeletionTombstone
DeviceStateEvent
```

## 11.1 `CaptureSegment`

```sql
CREATE TABLE capture_segment (
    segment_id TEXT PRIMARY KEY,
    device_id TEXT NOT NULL,
    boot_id TEXT NOT NULL,
    sequence_number INTEGER NOT NULL,

    started_at_utc_ms INTEGER NOT NULL,
    ended_at_utc_ms INTEGER NOT NULL,
    elapsed_start_ns INTEGER NOT NULL,
    elapsed_end_ns INTEGER NOT NULL,

    timezone_name TEXT NOT NULL,
    utc_offset_minutes INTEGER NOT NULL,

    encrypted_file_path TEXT NOT NULL,
    file_size_bytes INTEGER NOT NULL,
    sha256_ciphertext TEXT NOT NULL,

    codec TEXT NOT NULL,
    sample_rate_hz INTEGER NOT NULL,
    sample_count INTEGER NOT NULL,
    duration_ms INTEGER NOT NULL,

    upload_state TEXT NOT NULL,
    server_state TEXT NOT NULL,

    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL
);
```

## 11.2 State values

```text
upload_state:
    LOCAL
    QUEUED
    UPLOADING
    ACKNOWLEDGED
    RETRY_WAIT
    PERMANENT_FAILURE
    DELETED

server_state:
    UNKNOWN
    RECEIVED
    TRANSCRIBING
    TRANSCRIBED
    SESSIONIZED
    SUMMARIZED
    FAILED
```

---

# 12. Local encryption

Ambient audio is highly sensitive and shall be encrypted before remaining on disk.

## 12.1 Recommended envelope-encryption design

```text
Android Keystore
      ↓ protects
Device key-encryption key

Random per-file data-encryption key
      ↓
AES-256-GCM encryption of audio file
```

Per segment:

1. Generate a random 256-bit data-encryption key.
2. Generate a unique random GCM nonce.
3. Encrypt the audio with AES-GCM.
4. Wrap or encrypt the data key using a Keystore-backed device key.
5. Store the wrapped key and nonce in metadata.
6. Authenticate relevant metadata as additional authenticated data.

The Android Keystore keeps key material non-exportable and can bind it to secure hardware where available. Android security guidance recommends the Keystore for key management and robust cryptographic libraries such as Tink. 

Do not hardcode encryption keys, API tokens, or server secrets in the application package.

---

# 13. Upload scheduling

## 13.1 Separate recording from uploading

The recorder foreground service must not perform long uploads directly.

Use WorkManager for deferrable transfer jobs. Android WorkManager supports constraints such as unmetered networks, charging state, and battery-not-low. 

## 13.2 Default upload policy

Schedule an upload when any condition is met:

| Trigger | Default |
|---|---:|
| Oldest queued segment age | 15 minutes |
| Queued encrypted data | 25 MB |
| Number of queued segments | 20 |
| Device connected to charger | Upload immediately |
| User selects “sync now” | Upload immediately |
| Local free storage below threshold | Increase priority |

Network policy:

```text
Wi-Fi:
    allowed by default

Cellular:
    disabled by default
    user-configurable

Roaming:
    disabled by default
```

## 13.3 Batch semantics

“Batch upload” should mean:

- Reuse one network connection.
- Send a group manifest.
- Transfer several files in one synchronization operation.
- Retain independent checksums and acknowledgements for each segment.

Do not make one giant archive the only retry unit.

## 13.4 Upload protocol

Recommended sequence:

```text
POST /v1/upload-batches
        ↓
Server returns missing segment IDs
        ↓
PUT each missing encrypted blob
        ↓
POST /v1/upload-batches/{id}/complete
        ↓
Server verifies checksums
        ↓
Phone marks individual segments acknowledged
```

Example request:

```json
{
  "device_id": "phone-01",
  "segments": [
    {
      "segment_id": "019c...",
      "size_bytes": 193482,
      "sha256_ciphertext": "...",
      "started_at_utc": "2026-07-25T01:42:13.482Z"
    }
  ]
}
```

The server must make segment creation idempotent using `segment_id`.

## 13.5 Retry behavior

Use exponential backoff with jitter:

```text
1 minute
2 minutes
5 minutes
15 minutes
30 minutes
1 hour
maximum 6 hours
```

Authentication failures should not retry indefinitely. They should surface a user-visible error.

## 13.6 Deletion rule

The phone must not delete the local audio merely because upload bytes were transmitted.

Default deletion requirement:

```text
server checksum verified
AND transcript successfully stored
AND retention policy permits deletion
```

A more aggressive storage-saving mode may delete after verified server ingestion.

---

# 14. Server ingestion

## 14.1 Ingestion stages

```text
RECEIVE
  ↓
AUTHENTICATE
  ↓
VERIFY ID AND CHECKSUM
  ↓
STORE IMMUTABLE BLOB
  ↓
WRITE DATABASE RECORD
  ↓
ACKNOWLEDGE
  ↓
QUEUE TRANSCRIPTION
```

## 14.2 Storage layout

```text
audio/
└── device-id/
    └── 2026/
        └── 07/
            └── 25/
                └── <segment-id>.opus.enc
```

The object path is only an implementation detail. The database record is authoritative.

## 14.3 Idempotency

If a segment with the same `segment_id` already exists:

- Same checksum: return success.
- Different checksum: reject with a conflict.
- Never silently overwrite.

## 14.4 Audio validation

After decryption, validate:

- Container can be decoded.
- Sample count and duration are plausible.
- Audio is mono or can be downmixed.
- Duration is below configured limits.
- File is not empty.
- Decoded signal is finite and noncorrupt.
- Metadata duration approximately matches decoded duration.

---

# 15. Transcription service

## 15.1 Model separation

The transcription service shall use a dedicated ASR model through `faster-whisper`.

The summarization LLM shall not be responsible for producing the authoritative transcript.

`faster-whisper` supports word timestamps, batched inference, and optional Silero VAD integration. 

## 15.2 Recommended model profiles

Offer two server profiles:

```text
Accuracy profile:
    Whisper large-v3
    lower batch size
    archival-quality processing

Throughput profile:
    large-v3-turbo
    larger batch size
    lower latency
```

The actual default should be selected using measured word error rate and real-time factor on the available GPU.

## 15.3 Recommended transcription parameters

Initial configuration:

```python
segments, info = model.transcribe(
    audio_path,
    language=None,
    beam_size=5,
    word_timestamps=True,
    vad_filter=False,
    condition_on_previous_text=True,
    temperature=0.0,
)
```

### Why disable faster-whisper VAD initially

The phone has already preserved only a short amount of pre-roll, speech, and trailing silence. Additional server-side VAD trimming can:

- Change offset mappings.
- Complicate absolute timestamps.
- Remove quiet speech.
- Interact with Whisper’s timestamp generation.

For the primary archival path:

```text
Phone VAD:
    controls recording boundaries

Server ASR:
    transcribes the complete saved segment
```

A secondary server VAD may still be used to reject clear false triggers, but any trimming must produce an explicit mapping between original and trimmed time.

## 15.4 Context prompting

Use constrained previous context:

```text
Previous transcript tail:
    at most 100–200 tokens

Project vocabulary:
    configurable hotwords or prompt terms

Known people:
    user-editable list

Known technical terms:
    user-editable list
```

Do not provide an entire day’s transcript as the Whisper prompt. Incorrect previous text can propagate errors.

## 15.5 Preserve raw output

Store:

```text
raw_asr_text
raw_asr_segments
raw_asr_words
model_name
model_revision
decoder_parameters
language
language_probability
average_log_probability
no_speech_probability
processing_time
```

Never overwrite the raw ASR result.

A corrected transcript should be stored as a separate version.

## 15.6 Transcript versioning

```text
TranscriptVersion
├── version_id
├── segment_id
├── source_type
│   ├── ASR_RAW
│   ├── NORMALIZED
│   ├── USER_EDITED
│   └── RETRANSCRIBED
├── parent_version_id
├── model
├── text
└── created_at
```

---

# 16. Speaker diarization

Speaker diarization should be optional in version 1 and added after the base pipeline is reliable.

Use `pyannote.audio` or an equivalent self-hosted diarization system. `pyannote.audio` is an open-source toolkit specifically designed for speaker diarization, and its current community pipeline accepts mono 16 kHz audio. 

## 16.1 Diarize conversations, not tiny clips

Do not diarize each five-second capture segment independently.

Preferred process:

```text
Capture segments
    ↓
Initial session grouping
    ↓
Construct virtual session timeline
    ↓
Run diarization on session audio
    ↓
Map speaker intervals back to original segments
```

Speaker labels should initially be anonymous:

```text
SPEAKER_00
SPEAKER_01
SPEAKER_02
```

Voice identity enrollment should be a separate explicit feature.

---

# 17. Conversation sessionization

VAD segmentation and conversation segmentation are different problems.

## 17.1 Initial deterministic rules

Start a new conversation when:

- The time gap exceeds 10 minutes.
- The device reboots.
- Recording is manually paused.
- A major audio route change occurs.
- Location or connected-device context changes substantially, if context collection is enabled.

Usually keep segments in the same candidate conversation when:

- Gap is under 3 minutes.
- Nearby transcript topics are semantically related.
- Speaker composition is similar.
- Environment fingerprint is similar.

For gaps of 3–10 minutes, use a semantic classifier.

## 17.2 Sessionization LLM input

```json
{
  "previous_session_title": "Planning a spectroscopy measurement",
  "previous_transcript_tail": "...reduce the Raman pump power.",
  "next_transcript_head": "We should also check the polarization.",
  "gap_seconds": 113,
  "same_audio_environment": true
}
```

Expected response:

```json
{
  "same_conversation": true,
  "confidence": 0.94,
  "reason_code": "TOPIC_CONTINUATION"
}
```

The reason text is for diagnostics, not authoritative evidence.

---

# 18. Transcript normalization

The system shall maintain two transcript forms:

```text
Raw transcript:
    Exact ASR output

Normalized transcript:
    Punctuation, capitalization, paragraphing,
    obvious formatting corrections
```

Normalization must not silently change factual content.

Acceptable:

```text
raw:
"we should rerun it tomorrow with lower pump power"

normalized:
"We should rerun it tomorrow with lower pump power."
```

Not acceptable without evidence:

```text
raw:
"we should rerun it tomorrow"

normalized:
"We will rerun the transient absorption experiment tomorrow at 9:00 AM."
```

A normalization model should receive explicit instructions not to add names, times, measurements, or inferred context.

---

# 19. Summarization pipeline

## 19.1 Summarize conversations, not audio files

The summarization unit should normally be a reconstructed conversation.

```text
Several capture segments
        ↓
One normalized session transcript
        ↓
One structured conversation summary
```

## 19.2 Summary outputs

Each conversation summary should include:

```json
{
  "title": "Transient absorption measurement planning",
  "summary": "The speakers discussed repeating a measurement with lower pump power and checking Raman-pump polarization.",

  "topics": [
    "transient absorption",
    "pump power",
    "Raman polarization"
  ],

  "decisions": [
    {
      "text": "Repeat the measurement at lower pump power.",
      "confidence": 0.93,
      "evidence": [
        {
          "segment_id": "seg-123",
          "start_ms": 8420,
          "end_ms": 11920,
          "quote": "We should repeat it at lower pump power."
        }
      ]
    }
  ],

  "action_items": [
    {
      "text": "Repeat the measurement.",
      "owner": null,
      "due_at": null,
      "status": "OPEN",
      "confidence": 0.82,
      "evidence": [
        {
          "segment_id": "seg-123",
          "start_ms": 8420,
          "end_ms": 11920
        }
      ]
    }
  ],

  "questions": [
    {
      "text": "Should the Raman-pump polarization also be changed?",
      "answered": false
    }
  ],

  "people": [],
  "locations": [],
  "projects": [],
  "memory_candidates": [],
  "uncertainties": []
}
```

## 19.3 Evidence is mandatory

Every:

- Decision
- Task
- Deadline
- Personal fact
- Project fact
- Long-term memory candidate

must contain one or more evidence references.

The system should reject or downgrade extracted claims that lack evidence.

## 19.4 Relative date resolution

Relative dates must be resolved using the conversation’s capture time and time zone.

Example:

```text
Captured:
    Friday, July 24, 2026 at 2:00 PM America/New_York

Transcript:
    "Let's do it tomorrow morning."

Resolved:
    Saturday, July 25, 2026
    time precision: MORNING
```

Do not invent an exact clock time when only a daypart was stated.

Store both:

```json
{
  "original_expression": "tomorrow morning",
  "resolved_date": "2026-07-25",
  "resolved_time": null,
  "time_precision": "DAYPART",
  "timezone": "America/New_York"
}
```

## 19.5 LLM configuration

Recommended summarization settings:

```text
Temperature:             0.0–0.2
Output:                  Strict JSON
Schema validation:       Required
Maximum retries:         2
Evidence references:     Required
Unknown values:          null
Unsupported inferences:  Forbidden
```

Validation flow:

```text
LLM response
    ↓
JSON parse
    ↓
Schema validation
    ↓
Evidence validation
    ↓
Timestamp range validation
    ↓
Store or retry
```

## 19.6 Long conversations

For transcripts exceeding the model’s practical context:

```text
Full conversation
    ↓
Split into 15–30 minute semantic blocks
    ↓
Block extraction with evidence
    ↓
Final conversation synthesis
```

The final synthesis should consume:

- Block summaries.
- Extracted decisions and tasks.
- Evidence references.
- Relevant original transcript excerpts.

Do not repeatedly summarize summaries without preserving source references.

---

# 20. Hierarchical organization

The system should maintain these levels:

```text
Audio segment
    ↓
Transcript segment
    ↓
Conversation
    ↓
Conversation summary
    ↓
Daily digest
    ↓
Topic/project digest
    ↓
Long-term memory
```

## 20.1 Daily digest

Generate from completed conversation summaries rather than retranscribing audio.

Suggested structure:

```json
{
  "date": "2026-07-24",
  "overview": "...",
  "important_events": [],
  "decisions": [],
  "open_tasks": [],
  "people_interacted_with": [],
  "projects_discussed": [],
  "unresolved_questions": []
}
```

## 20.2 Memory promotion

A conversation fact should not automatically become permanent memory merely because it was mentioned once.

Promote a candidate when one or more conditions apply:

- The user explicitly pins it.
- It is repeated in multiple conversations.
- It represents a durable preference.
- It is an explicit commitment or deadline.
- It changes an existing project state.
- It concerns a named relationship or important event.
- It is referenced again later.

Memory records should contain:

```json
{
  "memory_id": "mem-...",
  "statement": "The preferred Raman-pump polarization is parallel.",
  "scope": "project",
  "confidence": 0.91,
  "valid_from": "2026-07-24",
  "valid_until": null,
  "status": "ACTIVE",
  "source_evidence": [],
  "supersedes_memory_id": null
}
```

Contradictory memories should be versioned rather than overwritten silently.

---

# 21. Server database model

Recommended core tables:

```text
device
capture_segment
audio_blob
transcription_job
transcript_version
transcript_segment
transcript_word
conversation
conversation_member
speaker
speaker_turn
summary_version
decision
action_item
entity
conversation_entity
memory_candidate
memory_item
embedding
processing_event
deletion_tombstone
```

## 21.1 Important relationship

```text
capture_segment
    1 → many transcript_versions

conversation
    many ↔ many capture_segments

conversation
    1 → many summary_versions

memory_item
    many → many evidence_spans
```

## 21.2 Immutable versus mutable data

Immutable:

- Original encrypted audio.
- Raw metadata.
- Raw ASR output.
- Model identifiers.
- Processing logs.

Versioned:

- Normalized transcript.
- Speaker labels.
- Conversation grouping.
- Summary.
- Memory records.

Mutable operational state:

- Upload status.
- Job status.
- Retention status.
- User tags.
- Task completion status.

---

# 22. Search and future recall

## 22.1 Use hybrid retrieval

Do not rely only on vector embeddings.

Combine:

```text
Full-text search
+
Semantic vector similarity
+
Date filters
+
Person filters
+
Project/topic filters
+
Conversation type
+
User-pinned importance
```

Full-text search is better for:

- Exact names.
- Technical terms.
- Numbers.
- Quoted phrases.
- Model or product identifiers.

Vector search is better for:

- Conceptual similarity.
- Paraphrased questions.
- Related discussions with different wording.

## 22.2 Recall response requirements

A recall answer should include:

- Direct answer.
- Date and conversation title.
- Supporting transcript excerpts.
- Audio playback links beginning near the evidence.
- Confidence or uncertainty where relevant.

Example:

```text
You decided to repeat the measurement using lower pump power
during a discussion on July 24, 2026.

Evidence:
“We should repeat it at lower pump power.”

[Open transcript] [Play from 14:31:42]
```

The recall LLM must not answer solely from summaries when supporting transcript evidence is available.

---

# 23. Privacy and user controls

Required controls:

- Permanent foreground notification while recording.
- Pause/resume button.
- Quick Settings tile.
- Optional automatic pause at selected locations.
- Optional pause when specified Bluetooth devices are connected.
- Audio retention duration.
- Transcript retention duration.
- “Never upload over cellular.”
- Delete one segment.
- Delete one conversation.
- Delete a date range.
- Delete all server data.
- Export transcript and metadata.
- View why a memory was created.
- Correct transcript text.
- Prevent selected conversations from becoming memory.
- Exclude selected locations or calendar events.
- Disable speaker recognition.

The application should visually distinguish:

```text
Listening:
    microphone active, no segment being saved

Recording:
    speech segment being persisted

Paused:
    microphone closed

Upload:
    stored audio being transferred
```

---

# 24. Retention policy

Recommended defaults:

```text
Local audio:
    retain until server transcript succeeds,
    plus a 24-hour safety window

Server audio:
    retain 30 days

Transcript:
    retain indefinitely unless deleted

Conversation summaries:
    retain indefinitely unless deleted

Failed or rejected audio:
    retain 7 days for diagnostics

Temporary decoded PCM:
    delete immediately after processing
```

All values must be user-configurable.

A privacy-oriented mode may delete server audio immediately after successful transcription and validation.

---

# 25. Reliability and recovery

## 25.1 Recorder crash recovery

At startup:

1. Scan for `.tmp` files.
2. Compare files with Room records.
3. Attempt to finalize recoverable audio.
4. Mark unrecoverable segments as corrupted.
5. Never upload a segment without a completed checksum.
6. Record a diagnostic event.

## 25.2 Sequence-gap detection

Each segment uses:

```text
device_id
boot_id
sequence_number
```

The server can detect:

```text
sequence 182
sequence 183
sequence 186
```

and report that 184–185 are missing.

## 25.3 Audio interruptions

Handle:

- Another application taking the microphone.
- Phone calls.
- Bluetooth route changes.
- USB microphone connection.
- Permission revocation.
- Device thermal pressure.
- Low storage.
- Encoder failure.
- AudioRecord dead-object errors.

The service should not silently pretend it is recording after microphone capture fails.

## 25.4 Server recovery

Every processing stage should be idempotent:

```text
INGESTED
TRANSCRIBED
SESSIONIZED
DIARIZED
SUMMARIZED
INDEXED
```

A failed summarization job must not require retranscription.

---

# 26. Battery and performance strategy

Priority order:

1. Keep audio processing native.
2. Capture mono at 16 kHz.
3. Run only VAD on the phone.
4. Reuse memory buffers.
5. Avoid per-frame Flutter events.
6. Avoid writing silence.
7. Compress completed speech segments.
8. Batch network activity.
9. Avoid frequent database writes.
10. Avoid a permanent application-owned wake lock unless measurement proves it necessary.

## 26.1 Initial engineering targets

These are design targets, not assumptions:

| Metric | Initial target |
|---|---:|
| VAD processing real-time factor | Below 0.02 |
| Recorder CPU average, quiet room | Below 3% of one core |
| Battery consumption, screen off | Below 1% per hour excluding heavy uploads |
| First-word clipping | Below 1% of tested utterances |
| Last-word clipping | Below 1% |
| Useful-speech capture recall | Above 95% in target environments |
| False-positive stored audio | Below 30 minutes per 24 hours |
| Continuous soak test | 72 hours without unrecovered failure |

Targets should be measured separately for:

- Quiet room.
- Pocket.
- Car.
- Television nearby.
- Outdoor walking.
- Laboratory ventilation noise.
- Music.
- Multiple speakers.
- Phone charging.
- Wi-Fi upload.
- Cellular upload.

---

# 27. Observability

## 27.1 On-device metrics

Collect locally:

```text
microphone_active_seconds
vad_frames_processed
vad_positive_frames
segments_created
segment_duration_seconds
misfires
audio_read_errors
encoder_errors
service_restarts
queued_bytes
upload_failures
battery_level_start/end
thermal-status changes
```

Telemetry should exclude audio and transcript content unless explicitly enabled.

## 27.2 Server metrics

```text
upload throughput
checksum failures
queued transcription duration
ASR real-time factor
GPU utilization
ASR failure rate
empty transcript rate
average segment duration
summary validation failure rate
LLM tokens per conversation
retrieval latency
storage growth
```

---

# 28. Testing plan

## 28.1 Unit tests

Test:

- Ring-buffer wraparound.
- Pre-roll extraction.
- VAD hysteresis.
- Silence timeout.
- Maximum-duration split.
- Timestamp conversion.
- Clock-change handling.
- Encryption/decryption.
- Atomic file finalization.
- Upload idempotency.
- Relative date resolution.
- Summary schema validation.
- Evidence-span validation.

## 28.2 Recorded-audio regression suite

Build a fixed audio corpus containing:

- Quiet speech.
- Distant speech.
- Whispered speech.
- Male and female speakers.
- Accented speech.
- Mixed English and Chinese.
- Lab fan noise.
- Vehicle noise.
- Television speech.
- Music with vocals.
- Keyboard noise.
- Dish and door sounds.
- Overlapping speakers.
- Long pauses.

For every VAD or ASR update, compare:

```text
speech recall
false-positive duration
boundary clipping
word error rate
timestamp error
processing time
```

## 28.3 Device matrix

Test at minimum:

- One recent Pixel or near-stock Android phone.
- One Samsung phone.
- One lower-memory Android device.
- Android 14.
- Android 15.
- Android 16 or later where available.

## 28.4 Soak tests

Required tests:

```text
8-hour screen-off test
24-hour normal-use test
72-hour unattended test
server unavailable for 24 hours
network switches Wi-Fi ↔ cellular
device reaches low storage
application process killed
wall clock changed manually
time zone changed
phone rebooted
```

Use Android battery and background-work tooling to measure actual behavior rather than estimating from CPU use alone. Android recommends batching and deferring network work and provides WorkManager constraints for this purpose. 

---

# 29. Recommended implementation phases

## Phase 1: Reliable local capture

Deliver:

- Native Kotlin foreground service.
- `AudioRecord`.
- Silero VAD.
- Ring buffer.
- WAV output.
- Room metadata.
- Manual segment browser.
- Eight-hour screen-off reliability.

Do not implement summarization yet.

## Phase 2: Encoding and synchronization

Deliver:

- Opus or AAC encoding.
- Local encryption.
- WorkManager upload queue.
- Idempotent server ingestion.
- Checksums.
- Server status display.
- Offline retry.

## Phase 3: Dedicated transcription

Deliver:

- faster-whisper worker.
- Raw transcript storage.
- Word timestamps.
- Model/version metadata.
- Transcript viewer.
- Retranscription support.
- Technical vocabulary prompt support.

## Phase 4: Conversation organization

Deliver:

- Time-gap sessionization.
- Semantic continuation classifier.
- Conversation timeline.
- Transcript normalization.
- User merge/split controls.

## Phase 5: Structured summarization

Deliver:

- JSON-schema output.
- Decisions.
- Tasks.
- Questions.
- Topics.
- Evidence references.
- Daily digests.
- Summary versioning.

## Phase 6: Recall system

Deliver:

- Full-text search.
- Embeddings.
- Hybrid retrieval.
- Evidence-backed answers.
- Timestamped audio playback.
- Memory candidate review.

## Phase 7: Speaker features

Deliver:

- Session-level diarization.
- Anonymous speaker labels.
- User naming of speakers.
- Optional voice enrollment.
- Speaker-filtered recall.

---

# 30. Recommended initial configuration

```yaml
capture:
  sample_rate_hz: 16000
  channels: 1
  sample_format: pcm16
  audio_source: voice_recognition
  fallback_audio_source: mic

vad:
  engine: silero_onnx
  frame_samples: 512
  start_probability: 0.60
  continue_probability: 0.35
  positive_frames_required: 3
  decision_window_frames: 5
  minimum_speech_ms: 350
  pre_roll_ms: 1500
  trailing_silence_ms: 1800
  post_roll_ms: 400
  maximum_segment_ms: 180000
  split_overlap_ms: 1000

encoding:
  preferred_codec: opus
  preferred_container: ogg
  bitrate_bps: 24000
  fallback_codec: aac_lc
  fallback_bitrate_bps: 32000

upload:
  wifi_enabled: true
  cellular_enabled: false
  roaming_enabled: false
  maximum_batch_segments: 20
  maximum_batch_bytes: 26214400
  maximum_queue_age_minutes: 15
  require_battery_not_low: true

transcription:
  backend: faster_whisper
  profile: accuracy
  word_timestamps: true
  server_vad: false
  beam_size: 5
  temperature: 0.0
  preserve_raw_output: true

sessionization:
  automatic_same_session_gap_seconds: 180
  semantic_decision_max_gap_seconds: 600
  force_new_session_after_pause: true

summarization:
  temperature: 0.1
  strict_json_schema: true
  evidence_required: true
  maximum_retries: 2
  resolve_relative_dates: true
  unknown_values_are_null: true

retention:
  local_audio_after_transcript_hours: 24
  server_audio_days: 30
  transcript_days: null
  temporary_pcm_minutes: 0
```

---

# 31. Final recommended architecture

```text
Flutter application
    │
    ├── User interface
    ├── Search
    ├── Settings
    └── Native control channel
            │
            ▼
Kotlin microphone foreground service
    │
    ├── AudioRecord, 16 kHz mono PCM16
    ├── Silero ONNX VAD
    ├── 1.5-second ring buffer
    ├── Hysteresis and silence hangover
    ├── Ogg Opus encoding
    ├── AES-GCM encryption
    ├── Room metadata
    └── WorkManager synchronization
            │
            ▼
Self-hosted ingestion service
    │
    ├── Idempotent segment API
    ├── Checksum verification
    ├── Encrypted object storage
    └── Job queue
            │
            ▼
faster-whisper worker
    │
    ├── Raw transcript
    ├── Segment timestamps
    ├── Approximate word timestamps
    ├── Confidence diagnostics
    └── Transcript versioning
            │
            ▼
Sessionization and optional diarization
            │
            ▼
OpenAI-compatible text LLM
    │
    ├── Normalization
    ├── Conversation summary
    ├── Decisions
    ├── Tasks
    ├── Entities
    ├── Evidence references
    └── Memory candidates
            │
            ▼
PostgreSQL/full-text/vector index
            │
            ▼
Evidence-backed future recall
```

The most important implementation principle is:

> **Preserve the original timeline and transcript as primary data. Treat summaries, tasks, entities, and memories as versioned interpretations that must remain traceable to their source.**
