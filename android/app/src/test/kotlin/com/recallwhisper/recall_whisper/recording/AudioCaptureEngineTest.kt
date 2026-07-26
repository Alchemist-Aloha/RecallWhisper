package com.recallwhisper.recall_whisper.recording

import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AudioCaptureEngineTest {
    @Test
    fun waitsForConfiguredPauseBeforeClosingSegment() {
        assertFalse(AudioCaptureEngine.reachedTrailingSilence(937, 30_000))
        assertTrue(AudioCaptureEngine.reachedTrailingSilence(938, 30_000))
    }

    @Test
    fun calculatesLongSegmentLimitWithoutIntegerOverflow() {
        assertEquals(2_880_000L, AudioCaptureEngine.samplesForDuration(16_000, 180_000))
    }
}
