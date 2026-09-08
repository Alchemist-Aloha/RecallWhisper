package com.recallwhisper.recall_whisper.recording

import org.junit.Assert.assertEquals
import org.junit.Test

class SummaryJsonParserTest {
    @Test
    fun unwrapsJsonStringEnvelope() {
        val result = parseSummaryObject(
            """{"json":"{\"summary\":\"A short summary.\"}"}""",
        )

        assertEquals("A short summary.", result.getString("summary"))
    }

    @Test
    fun acceptsBareJsonPrefix() {
        val result = parseSummaryObject(
            """json
            {"summary":"A prefixed summary."}""".trimIndent(),
        )

        assertEquals("A prefixed summary.", result.getString("summary"))
    }

    @Test
    fun acceptsJsonMarkdownFence() {
        val result = parseSummaryObject(
            """```json
            {"summary":"A fenced summary."}
            ```""".trimIndent(),
        )

        assertEquals("A fenced summary.", result.getString("summary"))
    }
}
