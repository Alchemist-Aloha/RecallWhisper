package com.recallwhisper.recall_whisper.recording

import androidx.work.NetworkType
import java.io.IOException
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.assertEquals
import org.junit.Test

class UploadSchedulerTest {
    @Test
    fun processNowDoesNotWaitForAnUnmeteredNetwork() {
        assertEquals(
            NetworkType.CONNECTED,
            ProcessingScheduler.requiredNetworkType(cellular = false, immediate = true),
        )
    }

    @Test
    fun backgroundProcessingKeepsTheWifiOnlyDefault() {
        assertEquals(
            NetworkType.UNMETERED,
            ProcessingScheduler.requiredNetworkType(cellular = false, immediate = false),
        )
    }

    @Test
    fun retriesOnlyTemporaryFailuresAndStopsAfterFiveAttempts() {
        assertTrue(RetryPolicy.shouldRetry(IOException("offline"), attempt = 0))
        assertTrue(RetryPolicy.shouldRetry(ApiException(503, "busy"), attempt = 0))
        assertFalse(RetryPolicy.shouldRetry(ApiException(401, "unauthorized"), attempt = 0))
        assertFalse(RetryPolicy.shouldRetry(IllegalArgumentException("bad config"), attempt = 0))
        assertFalse(RetryPolicy.shouldRetry(IOException("offline"), attempt = 4))
    }
}
