package com.recallwhisper.recall_whisper.recording

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Test

class DebugLogTest {
    @Test
    fun keepsOnlyLatestEntries() {
        val file = File.createTempFile("recallwhisper-debug", ".log")
        try {
            repeat(205) { DebugLog.append(file, "line-$it") }

            val lines = file.readLines()
            assertEquals(200, lines.size)
            assertEquals("line-5", lines.first())
            assertEquals("line-204", lines.last())
        } finally {
            file.delete()
        }
    }
}
