package com.recallwhisper.recall_whisper.recording

import org.junit.Assert.assertEquals
import org.junit.Test

class EpisodePlannerTest {
    @Test
    fun groupsNearbySegmentsAndPreservesRealBoundaries() {
        val groups = EpisodePlanner.group(
            listOf(
                segment("a", 0, 60_000),
                segment("b", 120_000, 180_000),
                segment("c", 600_001, 660_000),
                segment("d", 700_000, 760_000, bootId = "next-boot"),
            ),
            gapMs = 5 * 60_000,
            maxDurationMs = 30 * 60_000,
        )

        assertEquals(listOf(listOf("a", "b"), listOf("c"), listOf("d")), groups.map {
            it.map(CaptureSegment::segmentId)
        })
    }

    @Test
    fun capsAnEpisodeDurationEvenWithoutALongSilence() {
        val groups = EpisodePlanner.group(
            listOf(
                segment("a", 0, 60_000),
                segment("b", 25 * 60_000, 26 * 60_000),
                segment("c", 31 * 60_000, 32 * 60_000),
            ),
            gapMs = 30 * 60_000,
            maxDurationMs = 30 * 60_000,
        )

        assertEquals(listOf(2, 1), groups.map(List<CaptureSegment>::size))
    }

    private fun segment(
        id: String,
        start: Long,
        end: Long,
        bootId: String = "boot",
    ) = CaptureSegment(
        segmentId = id,
        deviceId = "device",
        bootId = bootId,
        sequenceNumber = start,
        startedAtUtcMs = start,
        endedAtUtcMs = end,
        elapsedStartNs = 0,
        elapsedEndNs = 0,
        timezoneName = "UTC",
        utcOffsetMinutes = 0,
        filePath = "/tmp/$id",
        fileSizeBytes = 1,
        sha256 = "hash",
        sha256Plaintext = null,
        encryptionVersion = 1,
        wrappedKey = null,
        wrapNonce = null,
        fileNonce = null,
        sampleCount = 1,
        durationMs = end - start,
        continuationGroupId = null,
        continuationIndex = 0,
        overlapMs = 0,
        transcriptText = id,
        createdAtMs = start,
        updatedAtMs = start,
    )
}
