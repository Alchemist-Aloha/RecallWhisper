package com.recallwhisper.recall_whisper.recording

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.io.File
import java.time.Duration

object UploadScheduler {
    fun enqueue(context: Context, immediate: Boolean = false) {
        val preferences = context.getSharedPreferences("recall_whisper", Context.MODE_PRIVATE)
        if (preferences.getString("transcription_url", "").isNullOrBlank()) return
        val network = if (preferences.getBoolean("cellular", false)) {
            NetworkType.CONNECTED
        } else {
            NetworkType.UNMETERED
        }
        val request = OneTimeWorkRequestBuilder<UploadWorker>()
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(network)
                    .setRequiresBatteryNotLow(!immediate)
                    .build(),
            )
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, Duration.ofMinutes(1))
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(
            "local_segment_processing",
            if (immediate) ExistingWorkPolicy.REPLACE else ExistingWorkPolicy.KEEP,
            request,
        )
    }
}

class UploadWorker(context: Context, parameters: WorkerParameters) :
    CoroutineWorker(context, parameters) {
    override suspend fun doWork(): Result {
        val preferences = applicationContext.getSharedPreferences(
            "recall_whisper",
            Context.MODE_PRIVATE,
        )
        val dao = RecorderDatabase.get(applicationContext).segments()
        val encryption = EncryptionManager()
        val api = DirectApiClient(applicationContext)
        for (segment in dao.pending()) {
            try {
                dao.updateProcessing(
                    segment.segmentId,
                    "PROCESSING",
                    "TRANSCRIBING",
                    segment.transcriptText,
                    segment.rawTranscriptJson,
                    segment.summaryJson,
                    null,
                    now(),
                )
                val audio = if (segment.encryptionVersion == 1) {
                    encryption.decrypt(segment)
                } else {
                    File(segment.filePath).readBytes()
                }
                val rawTranscript = api.transcribe(audio)
                audio.fill(0)
                val transcript = rawTranscript.getString("text").trim()
                check(transcript.isNotBlank()) { "Transcription API returned no text." }
                val summary = if (
                    preferences.getString("summarization_url", "").isNullOrBlank()
                ) {
                    null
                } else {
                    api.summarize(transcript)
                }
                dao.updateProcessing(
                    segment.segmentId,
                    "COMPLETE",
                    if (summary == null) "TRANSCRIBED" else "SUMMARIZED",
                    transcript,
                    rawTranscript.toString(),
                    summary,
                    null,
                    now(),
                )
            } catch (error: Exception) {
                dao.updateProcessing(
                    segment.segmentId,
                    "RETRY_WAIT",
                    "FAILED",
                    segment.transcriptText,
                    segment.rawTranscriptJson,
                    segment.summaryJson,
                    error.message ?: error.javaClass.simpleName,
                    now(),
                )
                return Result.retry()
            }
        }
        return Result.success()
    }

    private fun now() = System.currentTimeMillis()
}
