package com.recallwhisper.recall_whisper.recording

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
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

    @Test
    fun exactGapBoundaryKeepsSegmentsTogether() {
        val groups = EpisodePlanner.group(
            listOf(segment("a", 0, 60_000), segment("b", 120_000, 180_000)),
            gapMs = 60_000,
            maxDurationMs = 30 * 60_000,
        )

        assertEquals(1, groups.size)
    }

    @Test
    fun gapOneMillisecondBeyondTheBoundarySplits() {
        val groups = EpisodePlanner.group(
            listOf(segment("a", 0, 60_000), segment("b", 120_001, 180_000)),
            gapMs = 60_000,
            maxDurationMs = 30 * 60_000,
        )

        assertEquals(2, groups.size)
    }

    @Test
    fun exactMaximumDurationKeepsSegmentsTogether() {
        val groups = EpisodePlanner.group(
            listOf(segment("a", 0, 0), segment("b", 30 * 60_000, 30 * 60_000)),
            gapMs = 30 * 60_000,
            maxDurationMs = 30 * 60_000,
        )

        assertEquals(1, groups.size)
    }

    @Test
    fun durationOneMillisecondBeyondTheBoundarySplits() {
        val groups = EpisodePlanner.group(
            listOf(
                segment("a", 0, 0),
                segment("b", 30 * 60_000, 30 * 60_000 + 1),
            ),
            gapMs = 30 * 60_000,
            maxDurationMs = 30 * 60_000,
        )

        assertEquals(2, groups.size)
    }

    @Test
    fun overlappingSegmentsStayInOneGroup() {
        val groups = EpisodePlanner.group(
            listOf(segment("a", 0, 100_000), segment("b", 50_000, 80_000)),
            gapMs = 60_000,
            maxDurationMs = 30 * 60_000,
        )

        assertEquals(1, groups.size)
    }

    @Test
    fun emptyAndSingleSegmentInputsAreHandled() {
        assertTrue(
            EpisodePlanner.group(
                emptyList(),
                gapMs = 60_000,
                maxDurationMs = 30 * 60_000,
            ).isEmpty(),
        )
        assertEquals(
            1,
            EpisodePlanner.group(
                listOf(segment("a", 0, 60_000)),
                gapMs = 60_000,
                maxDurationMs = 30 * 60_000,
            ).size,
        )
    }

    @Test
    fun unsortedInputIsGroupedChronologically() {
        val groups = EpisodePlanner.group(
            listOf(segment("b", 120_000, 180_000), segment("a", 0, 60_000)),
            gapMs = 60_000,
            maxDurationMs = 30 * 60_000,
        )

        assertEquals(listOf(listOf("a", "b")), groups.map {
            it.map(CaptureSegment::segmentId)
        })
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
