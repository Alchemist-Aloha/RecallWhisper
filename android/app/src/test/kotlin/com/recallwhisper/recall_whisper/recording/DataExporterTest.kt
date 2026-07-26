package com.recallwhisper.recall_whisper.recording

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

class DataExporterTest {
    @Test
    fun exportsTranscriptAndStructuredSummary() {
        val segment = CaptureSegment(
            segmentId = "segment-1",
            deviceId = "phone",
            bootId = "boot",
            sequenceNumber = 1,
            startedAtUtcMs = 1000,
            endedAtUtcMs = 2000,
            elapsedStartNs = 1,
            elapsedEndNs = 2,
            timezoneName = "UTC",
            utcOffsetMinutes = 0,
            filePath = "audio.enc",
            fileSizeBytes = 10,
            sha256 = "abc",
            sha256Plaintext = "def",
            encryptionVersion = 1,
            wrappedKey = "key",
            wrapNonce = "wrap",
            fileNonce = "file",
            sampleCount = 16000,
            durationMs = 1000,
            continuationGroupId = null,
            continuationIndex = 0,
            overlapMs = 0,
            transcriptText = "A decision was made.",
            rawTranscriptJson = """{"text":"A decision was made."}""",
            summaryJson = """{"summary":"Decision captured."}""",
            createdAtMs = 1000,
            updatedAtMs = 2000,
        )
        val export = JSONObject(DataExporter.toJson(listOf(segment), 3000))
        val value = export.getJSONArray("segments").getJSONObject(0)
        assertEquals("A decision was made.", value.getString("transcript"))
        assertEquals(
            "Decision captured.",
            value.getJSONObject("summary").getString("summary"),
        )
    }
}
