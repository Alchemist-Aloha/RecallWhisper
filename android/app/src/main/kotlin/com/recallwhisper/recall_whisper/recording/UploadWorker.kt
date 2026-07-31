package com.recallwhisper.recall_whisper.recording

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.io.File
import java.time.Duration
import java.util.UUID

object ProcessingScheduler {
    private const val TRANSCRIPTION_WORK = "segment_transcription"
    private const val SUMMARY_WORK = "segment_summarization"

    fun hasTranscriptionConfig(context: Context) =
        hasEndpoint(context, "transcription_url")

    fun hasSummaryConfig(context: Context) =
        hasEndpoint(context, "summarization_url")

    fun enqueueTranscription(
        context: Context,
        immediate: Boolean = false,
        resubmitted: Boolean = false,
    ): Boolean {
        if (!hasTranscriptionConfig(context)) return false
        enqueue<TranscriptionWorker>(
            context,
            TRANSCRIPTION_WORK,
            immediate,
            resubmitted,
        )
        return true
    }

    fun enqueueSummary(
        context: Context,
        immediate: Boolean = false,
        resubmitted: Boolean = false,
    ): Boolean {
        if (!hasSummaryConfig(context)) return false
        enqueue<SummaryWorker>(context, SUMMARY_WORK, immediate, resubmitted)
        return true
    }

    fun stopTranscription(context: Context) =
        WorkManager.getInstance(context).cancelUniqueWork(TRANSCRIPTION_WORK)

    fun stopSummary(context: Context) =
        WorkManager.getInstance(context).cancelUniqueWork(SUMMARY_WORK)

    private fun hasEndpoint(context: Context, key: String) =
        !context.getSharedPreferences("recall_whisper", Context.MODE_PRIVATE)
            .getString(key, "").isNullOrBlank()

    private inline fun <reified T : CoroutineWorker> enqueue(
        context: Context,
        name: String,
        immediate: Boolean,
        resubmitted: Boolean,
    ) {
        val preferences = context.getSharedPreferences("recall_whisper", Context.MODE_PRIVATE)
        val request = OneTimeWorkRequestBuilder<T>()
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(
                        requiredNetworkType(
                            preferences.getBoolean("cellular", false),
                            immediate,
                        ),
                    )
                    .setRequiresBatteryNotLow(!immediate)
                    .build(),
            )
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, Duration.ofMinutes(1))
            .apply {
                if (immediate) {
                    setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                }
            }
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(
            name,
            when {
                resubmitted -> ExistingWorkPolicy.APPEND_OR_REPLACE
                immediate -> ExistingWorkPolicy.REPLACE
                else -> ExistingWorkPolicy.KEEP
            },
            request,
        )
    }

    internal fun requiredNetworkType(cellular: Boolean, immediate: Boolean) =
        if (cellular || immediate) NetworkType.CONNECTED else NetworkType.UNMETERED
}

open class TranscriptionWorker(context: Context, parameters: WorkerParameters) :
    CoroutineWorker(context, parameters) {
    override suspend fun doWork(): Result {
        val dao = RecorderDatabase.get(applicationContext).segments()
        val encryption = EncryptionManager()
        val api = DirectApiClient(applicationContext)
        var retry = false
        val segments = dao.pendingTranscription()
        DebugLog.info(applicationContext, "Transcription worker started (${segments.size} pending)")
        for (segment in segments) {
            if (isStopped) break
            try {
                dao.updateTranscription(
                    segment.segmentId,
                    "PROCESSING",
                    "PROCESSING",
                    "TRANSCRIBING",
                    segment.transcriptText,
                    segment.rawTranscriptJson,
                    null,
                    now(),
                )
                val audio = if (segment.encryptionVersion == 1) {
                    encryption.decrypt(segment)
                } else {
                    File(segment.filePath).readBytes()
                }
                val rawTranscript = try {
                    api.transcribe(audio)
                } finally {
                    audio.fill(0)
                }
                if (isStopped) break
                val transcript = transcriptionText(rawTranscript)
                dao.updateTranscription(
                    segment.segmentId,
                    if (transcript == null) "EMPTY" else "COMPLETE",
                    "COMPLETE",
                    if (transcript == null) "EMPTY" else "TRANSCRIBED",
                    transcript,
                    rawTranscript.toString(),
                    null,
                    now(),
                )
                DebugLog.info(
                    applicationContext,
                    "Transcription ${segment.segmentId} ${if (transcript == null) "empty" else "complete"}",
                )
            } catch (error: Exception) {
                if (isStopped) break
                val canRetry = RetryPolicy.shouldRetry(error, runAttemptCount)
                dao.updateTranscription(
                    segment.segmentId,
                    if (canRetry) "RETRY_WAIT" else "FAILED",
                    if (canRetry) "RETRY_WAIT" else "FAILED",
                    "FAILED",
                    segment.transcriptText,
                    segment.rawTranscriptJson,
                    error.message ?: error.javaClass.simpleName,
                    now(),
                )
                retry = retry || canRetry
                DebugLog.error(
                    applicationContext,
                    "Transcription ${segment.segmentId} failed (retry=$canRetry)",
                    error,
                )
            }
        }
        DebugLog.info(applicationContext, "Transcription worker finished (retry=$retry)")
        return if (retry) Result.retry() else Result.success()
    }

    private fun now() = System.currentTimeMillis()
}

@Deprecated("Kept so already-scheduled WorkManager rows survive app upgrades.")
class UploadWorker(context: Context, parameters: WorkerParameters) :
    TranscriptionWorker(context, parameters)

class SummaryWorker(context: Context, parameters: WorkerParameters) :
    CoroutineWorker(context, parameters) {
    override suspend fun doWork(): Result {
        val database = RecorderDatabase.get(applicationContext)
        val dao = database.segments()
        val api = DirectApiClient(applicationContext)
        val preferences = applicationContext.getSharedPreferences(
            "recall_whisper",
            Context.MODE_PRIVATE,
        )
        val groups = EpisodePlanner.group(
            dao.pendingSummary(),
            preferences.getInt("episode_gap_minutes", 5) * 60_000L,
            preferences.getInt("episode_max_minutes", 30) * 60_000L,
        )
        DebugLog.info(applicationContext, "Summary worker started (${groups.size} episodes)")
        var retry = false
        for (segments in groups) {
            if (isStopped) break
            try {
                segments.forEach { mark(it, "PROCESSING", "SUMMARIZING", null) }
                val topics = dao.recentTopics()
                val result = api.summarizeEpisode(segments, topics)
                if (isStopped) break
                val topicsById = topics.associateBy { it.topicId }
                val requestedId = result.optString("canonical_topic_id")
                    .takeUnless { it.isBlank() || it == "null" }
                val topicId = requestedId?.takeIf(topicsById::containsKey)
                    ?: "top_${UUID.randomUUID()}"
                val episodeId = "ep_" + UUID.nameUUIDFromBytes(
                    segments.joinToString("|") { it.segmentId }.toByteArray(),
                )
                val first = segments.first()
                val last = segments.last()
                val summary = text(result, "summary")
                check(summary.isNotBlank()) { "Episode summary was empty." }
                val localTitle = text(result, "local_title", "Topic episode")
                val canonicalTitle = text(result, "canonical_title", localTitle)
                database.runInTransaction {
                    dao.saveTopic(
                        Topic(
                            topicId = topicId,
                            canonicalTitle = canonicalTitle,
                            description = text(result, "topic_description", summary),
                            currentSummary = text(result, "topic_summary", summary),
                            topicPathJson = result.optJSONArray("topic_path")
                                ?.toString() ?: "[]",
                            firstSeenUtcMs = topicsById[topicId]?.firstSeenUtcMs
                                ?: first.startedAtUtcMs,
                            lastSeenUtcMs = last.endedAtUtcMs,
                        ),
                    )
                    dao.saveEpisode(
                        TopicEpisode(
                            episodeId = episodeId,
                            topicId = topicId,
                            startedAtUtcMs = first.startedAtUtcMs,
                            endedAtUtcMs = last.endedAtUtcMs,
                            localTitle = localTitle,
                            summaryJson = result.toString(),
                            keywordsJson = result.optJSONArray("keywords")
                                ?.toString() ?: "[]",
                            secondaryTopicsJson = result.optJSONArray("secondary_topics")
                                ?.toString() ?: "[]",
                        ),
                    )
                    dao.saveEpisodeSegments(
                        segments.mapIndexed { index, segment ->
                            EpisodeSegment(episodeId, segment.segmentId, index)
                        },
                    )
                    segments.forEach {
                        dao.updateSummary(
                            it.segmentId,
                            "COMPLETE",
                            "SUMMARIZED",
                            result.toString(),
                            null,
                            now(),
                        )
                    }
                }
                DebugLog.info(applicationContext, "Summary $episodeId complete")
            } catch (error: Exception) {
                if (isStopped) break
                val canRetry = RetryPolicy.shouldRetry(error, runAttemptCount)
                segments.forEach {
                    mark(
                        it,
                        if (canRetry) "RETRY_WAIT" else "FAILED",
                        "FAILED",
                        error.message ?: error.javaClass.simpleName,
                    )
                }
                retry = retry || canRetry
                DebugLog.error(
                    applicationContext,
                    "Summary failed (retry=$canRetry)",
                    error,
                )
            }
        }
        DebugLog.info(applicationContext, "Summary worker finished (retry=$retry)")
        return if (retry) Result.retry() else Result.success()
    }

    private fun mark(segment: CaptureSegment, state: String, serverState: String, error: String?) {
        RecorderDatabase.get(applicationContext).segments().updateSummary(
            segment.segmentId,
            state,
            serverState,
            segment.summaryJson,
            error,
            now(),
        )
    }

    private fun text(json: org.json.JSONObject, key: String, fallback: String = "") =
        json.optString(key).trim().takeUnless { it.isBlank() || it == "null" } ?: fallback

    private fun now() = System.currentTimeMillis()
}

internal fun transcriptionText(response: org.json.JSONObject): String? =
    response.optString("text").trim().takeUnless { it.isBlank() || it == "null" }

internal object RetryPolicy {
    const val MAX_ATTEMPTS = 5

    fun shouldRetry(error: Exception, attempt: Int): Boolean {
        if (attempt + 1 >= MAX_ATTEMPTS || error is IllegalArgumentException) return false
        return error !is ApiException || error.status == 408 || error.status == 429 ||
            error.status in 500..599
    }
}

internal object EpisodePlanner {
    fun group(
        segments: List<CaptureSegment>,
        gapMs: Long,
        maxDurationMs: Long,
    ): List<List<CaptureSegment>> {
        if (segments.isEmpty()) return emptyList()
        val groups = mutableListOf<MutableList<CaptureSegment>>()
        segments.sortedBy { it.startedAtUtcMs }.forEach { segment ->
            val current = groups.lastOrNull()
            val boundary = current == null ||
                segment.bootId != current.last().bootId ||
                segment.startedAtUtcMs - current.last().endedAtUtcMs > gapMs ||
                segment.endedAtUtcMs - current.first().startedAtUtcMs > maxDurationMs
            if (boundary) groups += mutableListOf(segment) else current.add(segment)
        }
        return groups
    }
}
