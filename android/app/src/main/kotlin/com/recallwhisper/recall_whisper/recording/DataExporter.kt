package com.recallwhisper.recall_whisper.recording

import org.json.JSONArray
import org.json.JSONObject

object DataExporter {
    fun toJson(
        segments: List<CaptureSegment>,
        exportedAtMs: Long,
        topics: List<Topic> = emptyList(),
        episodes: List<TopicEpisode> = emptyList(),
    ): String =
        JSONObject().apply {
            put("format", "RecallWhisper export")
            put("version", 1)
            put("exported_at_utc_ms", exportedAtMs)
            put(
                "segments",
                JSONArray().apply {
                    segments.forEach { segment ->
                        put(
                            JSONObject().apply {
                                put("segment_id", segment.segmentId)
                                put("device_id", segment.deviceId)
                                put("boot_id", segment.bootId)
                                put("sequence_number", segment.sequenceNumber)
                                put("started_at_utc_ms", segment.startedAtUtcMs)
                                put("ended_at_utc_ms", segment.endedAtUtcMs)
                                put("timezone_name", segment.timezoneName)
                                put("utc_offset_minutes", segment.utcOffsetMinutes)
                                put("duration_ms", segment.durationMs)
                                put("sample_rate_hz", segment.sampleRateHz)
                                put("sample_count", segment.sampleCount)
                                put("sha256_ciphertext", segment.sha256)
                                put("processing_state", segment.serverState)
                                put("transcript", segment.transcriptText)
                                put("raw_transcription", jsonValue(segment.rawTranscriptJson))
                                put("summary", jsonValue(segment.summaryJson))
                                put("processing_error", segment.processingError)
                            },
                        )
                    }
                },
            )
            put("topics", JSONArray(topics.map {
                JSONObject()
                    .put("topic_id", it.topicId)
                    .put("canonical_title", it.canonicalTitle)
                    .put("description", it.description)
                    .put("current_summary", it.currentSummary)
                    .put("topic_path", jsonValue(it.topicPathJson))
                    .put("first_seen_utc_ms", it.firstSeenUtcMs)
                    .put("last_seen_utc_ms", it.lastSeenUtcMs)
            }))
            put("topic_episodes", JSONArray(episodes.map {
                JSONObject()
                    .put("episode_id", it.episodeId)
                    .put("topic_id", it.topicId)
                    .put("started_at_utc_ms", it.startedAtUtcMs)
                    .put("ended_at_utc_ms", it.endedAtUtcMs)
                    .put("local_title", it.localTitle)
                    .put("summary", jsonValue(it.summaryJson))
                    .put("keywords", jsonValue(it.keywordsJson))
                    .put("secondary_topics", jsonValue(it.secondaryTopicsJson))
                    .put("segmentation_status", it.segmentationStatus)
            }))
        }.toString(2)

    private fun jsonValue(value: String?): Any? {
        if (value == null) return null
        return runCatching { JSONObject(value) }.getOrElse {
            runCatching { JSONArray(value) }.getOrDefault(value)
        }
    }
}
