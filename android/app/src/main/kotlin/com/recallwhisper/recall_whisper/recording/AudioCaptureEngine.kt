package com.recallwhisper.recall_whisper.recording

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max

class AudioCaptureEngine(
    private val context: Context,
    private val onState: (String) -> Unit,
    private val onSegment: (String, Long) -> Unit,
    private val onError: (String, String) -> Unit,
) {
    private val running = AtomicBoolean()
    private var thread: Thread? = null
    private var recorder: AudioRecord? = null

    @SuppressLint("MissingPermission")
    fun start() {
        if (!running.compareAndSet(false, true)) return
        thread = Thread({
            try {
                capture()
            } catch (error: Throwable) {
                if (running.get()) onError("capture_failed", error.message ?: error.javaClass.simpleName)
            } finally {
                recorder?.runCatching { stop() }
                recorder?.release()
                recorder = null
                running.set(false)
            }
        }, "RecallWhisperCapture").apply {
            priority = Thread.MAX_PRIORITY
            start()
        }
    }

    fun stop() {
        running.set(false)
        recorder?.runCatching { stop() }
        thread?.join(2_000)
        thread = null
    }

    @SuppressLint("MissingPermission")
    private fun capture() {
        val minimum = AudioRecord.getMinBufferSize(
            SileroVad.SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        check(minimum > 0) { "AudioRecord does not support 16 kHz mono PCM16" }
        recorder = createRecorder(MediaRecorder.AudioSource.VOICE_RECOGNITION, max(minimum * 4, 16_384))
            .takeIf { it.state == AudioRecord.STATE_INITIALIZED }
            ?: createRecorder(MediaRecorder.AudioSource.MIC, max(minimum * 4, 16_384))
        val audio = recorder!!
        check(audio.state == AudioRecord.STATE_INITIALIZED) { "Microphone initialization failed" }

        val directory = File(context.filesDir, "segments").apply { mkdirs() }
        recoverTemporaryFiles(directory)
        val database = RecorderDatabase.get(context).segments()
        val ring = ShortRingBuffer(PRE_ROLL_SAMPLES)
        val overlap = ShortRingBuffer(OVERLAP_SAMPLES)
        val history = ArrayDeque<Boolean>(DECISION_FRAMES)
        val trailingSilenceMs = context.getSharedPreferences(
            "recall_whisper",
            Context.MODE_PRIVATE,
        ).getInt("conversation_pause_ms_v2", TRAILING_SILENCE_MS)
        val readBuffer = ShortArray(4096)
        val frame = ShortArray(SileroVad.FRAME_SAMPLES)
        var frameSize = 0
        var writer: WavFile? = null
        var speechFrames = 0
        var silenceFrames = 0
        var startedWallMs = 0L
        var startedElapsedNs = 0L
        var continuationGroup: String? = null
        var continuationIndex = 0
        var segmentSequence = 0L

        fun begin(samples: ShortArray, overlapMs: Int) {
            val id = UUID.randomUUID().toString()
            if (continuationGroup == null) continuationGroup = id
            writer = WavFile(directory, id).also { it.write(samples) }
            val preMs = samples.size * 1000L / SileroVad.SAMPLE_RATE
            startedWallMs = System.currentTimeMillis() - preMs
            startedElapsedNs = SystemClock.elapsedRealtimeNanos() - preMs * 1_000_000
            segmentSequence = database.nextSequence()
            speechFrames = 0
            silenceFrames = 0
            onState("RECORDING")
        }

        fun finalize(valid: Boolean, split: Boolean = false) {
            val current = writer ?: return
            writer = null
            if (!valid) {
                current.abort()
            } else {
                val plainFile = current.finish()
                val encrypted = EncryptionManager().encrypt(plainFile, current.id)
                val endedWall = startedWallMs + current.sampleCount * 1000 / SileroVad.SAMPLE_RATE
                val endedElapsed = startedElapsedNs +
                    current.sampleCount * 1_000_000_000 / SileroVad.SAMPLE_RATE
                val now = System.currentTimeMillis()
                val zone = ZoneId.systemDefault()
                database.insert(
                    CaptureSegment(
                        segmentId = current.id,
                        deviceId = "${Build.MANUFACTURER}-${Build.MODEL}",
                        bootId = Settings.Global.getInt(
                            context.contentResolver,
                            Settings.Global.BOOT_COUNT,
                            0,
                        ).toString(),
                        sequenceNumber = segmentSequence,
                        startedAtUtcMs = startedWallMs,
                        endedAtUtcMs = endedWall,
                        elapsedStartNs = startedElapsedNs,
                        elapsedEndNs = endedElapsed,
                        timezoneName = zone.id,
                        utcOffsetMinutes = zone.rules.getOffset(Instant.ofEpochMilli(startedWallMs))
                            .totalSeconds / 60,
                        filePath = encrypted.file.absolutePath,
                        fileSizeBytes = encrypted.file.length(),
                        sha256 = encrypted.sha256Ciphertext,
                        sha256Plaintext = encrypted.sha256Plaintext,
                        encryptionVersion = 1,
                        wrappedKey = encrypted.wrappedKey,
                        wrapNonce = encrypted.wrapNonce,
                        fileNonce = encrypted.fileNonce,
                        sampleCount = current.sampleCount,
                        durationMs = current.sampleCount * 1000 / SileroVad.SAMPLE_RATE,
                        continuationGroupId = continuationGroup.takeIf { continuationIndex > 0 || split },
                        continuationIndex = continuationIndex,
                        overlapMs = if (continuationIndex == 0) 0 else OVERLAP_MS,
                        createdAtMs = now,
                        updatedAtMs = now,
                    ),
                )
                onSegment(current.id, current.sampleCount * 1000 / SileroVad.SAMPLE_RATE)
                UploadScheduler.enqueue(context)
            }
            if (!split) {
                continuationGroup = null
                continuationIndex = 0
                overlap.clear()
                onState("LISTENING")
            }
        }

        SileroVad(context).use { vad ->
            audio.startRecording()
            check(audio.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                "Microphone did not enter recording state"
            }
            onState("LISTENING")
            while (running.get()) {
                val count = audio.read(readBuffer, 0, readBuffer.size, AudioRecord.READ_BLOCKING)
                if (count == AudioRecord.ERROR_DEAD_OBJECT) error("Microphone disconnected")
                if (count < 0) error("AudioRecord read failed: $count")
                for (index in 0 until count) {
                    frame[frameSize++] = readBuffer[index]
                    if (frameSize != frame.size) continue
                    frameSize = 0
                    val probability = vad.probability(frame)
                    ring.add(frame)
                    if (writer == null) {
                        history.addLast(probability >= START_PROBABILITY)
                        if (history.size > DECISION_FRAMES) history.removeFirst()
                        if (history.size == DECISION_FRAMES &&
                            history.count { it } >= START_POSITIVE_FRAMES
                        ) {
                            begin(ring.snapshot(), 0)
                            overlap.add(ring.snapshot())
                            history.clear()
                        }
                        continue
                    }

                    writer!!.write(frame)
                    overlap.add(frame)
                    if (probability >= CONTINUE_PROBABILITY) {
                        speechFrames++
                        silenceFrames = 0
                    } else {
                        silenceFrames++
                    }

                    if (writer!!.sampleCount >= MAX_SEGMENT_SAMPLES) {
                        finalize(valid = true, split = true)
                        continuationIndex++
                        begin(overlap.snapshot(), OVERLAP_MS)
                    } else if (reachedTrailingSilence(silenceFrames, trailingSilenceMs)) {
                        finalize(speechFrames * FRAME_MS >= MINIMUM_SPEECH_MS)
                        vad.reset()
                        ring.clear()
                        history.clear()
                    }
                }
            }
        }
        finalize(speechFrames * FRAME_MS >= MINIMUM_SPEECH_MS)
    }

    @SuppressLint("MissingPermission")
    private fun createRecorder(source: Int, bufferBytes: Int) = AudioRecord.Builder()
        .setAudioSource(source)
        .setAudioFormat(
            AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(SileroVad.SAMPLE_RATE)
                .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                .build(),
        )
        .setBufferSizeInBytes(bufferBytes)
        .build()

    private fun recoverTemporaryFiles(directory: File) {
        directory.listFiles { file -> file.name.endsWith(".wav.tmp") }?.forEach {
            it.renameTo(File(it.parentFile, "${it.name}.corrupt"))
        }
    }

    companion object {
        const val START_PROBABILITY = 0.60f
        const val CONTINUE_PROBABILITY = 0.35f
        const val FRAME_MS = 32
        const val MINIMUM_SPEECH_MS = 350
        const val PRE_ROLL_MS = 1500
        const val OVERLAP_MS = 1000
        const val TRAILING_SILENCE_MS = 30_000
        const val MAX_SEGMENT_MS = 180_000
        const val DECISION_FRAMES = 5
        const val START_POSITIVE_FRAMES = 3
        fun reachedTrailingSilence(frames: Int, timeoutMs: Int) =
            frames * FRAME_MS >= timeoutMs

        fun samplesForDuration(sampleRate: Int, durationMs: Int) =
            sampleRate.toLong() * durationMs / 1000

        private const val PRE_ROLL_SAMPLES = SileroVad.SAMPLE_RATE * PRE_ROLL_MS / 1000
        private const val OVERLAP_SAMPLES = SileroVad.SAMPLE_RATE * OVERLAP_MS / 1000
        private val MAX_SEGMENT_SAMPLES =
            samplesForDuration(SileroVad.SAMPLE_RATE, MAX_SEGMENT_MS)
    }
}
