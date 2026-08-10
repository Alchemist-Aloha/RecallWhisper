package com.recallwhisper.recall_whisper.recording

import androidx.work.NetworkType
import java.io.IOException
import org.json.JSONObject
import org.junit.Assert.assertNull
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
    fun cellularPreferenceAllowsAnyNetworkEvenInTheBackground() {
        assertEquals(
            NetworkType.CONNECTED,
            ProcessingScheduler.requiredNetworkType(cellular = true, immediate = false),
        )
        assertEquals(
            NetworkType.CONNECTED,
            ProcessingScheduler.requiredNetworkType(cellular = true, immediate = true),
        )
    }

    @Test
    fun retriesOnlyTemporaryFailuresAndStopsAfterFiveAttempts() {
        assertTrue(RetryPolicy.shouldRetry(IOException("offline"), attempt = 0))
        assertTrue(RetryPolicy.shouldRetry(ApiException(408, "timeout"), attempt = 0))
        assertTrue(RetryPolicy.shouldRetry(ApiException(429, "busy"), attempt = 3))
        assertTrue(RetryPolicy.shouldRetry(ApiException(500, "down"), attempt = 0))
        assertTrue(RetryPolicy.shouldRetry(ApiException(599, "down"), attempt = 0))
        assertFalse(RetryPolicy.shouldRetry(ApiException(400, "bad request"), attempt = 0))
        assertTrue(RetryPolicy.shouldRetry(ApiException(503, "busy"), attempt = 0))
        assertFalse(RetryPolicy.shouldRetry(ApiException(401, "unauthorized"), attempt = 0))
        assertFalse(RetryPolicy.shouldRetry(ApiException(600, "invalid"), attempt = 0))
        assertFalse(RetryPolicy.shouldRetry(IllegalArgumentException("bad config"), attempt = 0))
        assertFalse(RetryPolicy.shouldRetry(IOException("offline"), attempt = 4))
    }

    @Test
    fun theFifthAttemptNeverRetriesEvenTemporaryFailures() {
        assertFalse(RetryPolicy.shouldRetry(ApiException(408, "timeout"), attempt = 4))
        assertFalse(RetryPolicy.shouldRetry(ApiException(429, "busy"), attempt = 4))
        assertFalse(RetryPolicy.shouldRetry(ApiException(500, "down"), attempt = 4))
        assertFalse(RetryPolicy.shouldRetry(ApiException(503, "busy"), attempt = 4))
    }

    @Test
    fun temporaryFailuresAreStillRetryableOnTheFourthAttempt() {
        assertTrue(RetryPolicy.shouldRetry(ApiException(408, "timeout"), attempt = 3))
        assertTrue(RetryPolicy.shouldRetry(ApiException(429, "busy"), attempt = 3))
        assertTrue(RetryPolicy.shouldRetry(ApiException(503, "busy"), attempt = 3))
        assertTrue(RetryPolicy.shouldRetry(IOException("offline"), attempt = 3))
    }

    @Test
    fun otherProtocolErrorsAreNeverRetried() {
        assertFalse(RetryPolicy.shouldRetry(ApiException(403, "forbidden"), attempt = 0))
        assertFalse(RetryPolicy.shouldRetry(ApiException(404, "missing"), attempt = 0))
        assertFalse(RetryPolicy.shouldRetry(ApiException(302, "redirect"), attempt = 0))
        assertFalse(RetryPolicy.shouldRetry(ApiException(100, "continue"), attempt = 0))
        assertFalse(RetryPolicy.shouldRetry(ApiException(204, "no content"), attempt = 0))
    }

    @Test
    fun blankTranscriptionResponsesAreEmptyRatherThanFailures() {
        assertNull(transcriptionText(JSONObject()))
        assertNull(transcriptionText(JSONObject().put("text", "")))
        assertNull(transcriptionText(JSONObject().put("text", " \n ")))
        assertNull(transcriptionText(JSONObject().put("text", JSONObject.NULL)))
        assertEquals("spoken words", transcriptionText(JSONObject().put("text", " spoken words ")))
    }
}
