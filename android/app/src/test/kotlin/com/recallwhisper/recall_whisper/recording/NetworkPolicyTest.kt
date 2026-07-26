package com.recallwhisper.recall_whisper.recording

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class NetworkPolicyTest {
    @Test
    fun blocksHttpUnlessExplicitlyEnabled() {
        assertThrows(IllegalArgumentException::class.java) {
            NetworkPolicy.requireAllowedUrl("http://192.168.1.2:8080", false)
        }
        assertEquals(
            "http://192.168.1.2:8080",
            NetworkPolicy.requireAllowedUrl("http://192.168.1.2:8080", true),
        )
        assertEquals(
            "https://recall.example",
            NetworkPolicy.requireAllowedUrl("https://recall.example", false),
        )
    }
}
