package com.recallwhisper.recall_whisper.recording

import org.junit.Assert.assertEquals
import org.junit.Test

class TodoExtractorTest {
    @Test
    fun extractsPlainStringItems() {
        val summary = """{"action_items": ["Buy milk", "Email Alice"]}"""

        assertEquals(listOf("Buy milk", "Email Alice"), TodoExtractor.extract(summary))
    }

    @Test
    fun extractsFromObjectsPreferringTextOverTaskAndDescription() {
        val summary = """
            {"action_items": [
                {"task": "Task fallback", "text": "Text wins"},
                {"description": "From description"},
                {"task": "From task"}
            ]}
        """.trimIndent()

        assertEquals(
            listOf("Text wins", "From description", "From task"),
            TodoExtractor.extract(summary),
        )
    }

    @Test
    fun trimsValuesAndDropsBlankOrNullEntries() {
        val summary = """
            {"action_items": ["  Call Bob  ", "", "   ", "null", {"text": null}, {"task": ""}]}
        """.trimIndent()

        assertEquals(listOf("Call Bob"), TodoExtractor.extract(summary))
    }

    @Test
    fun returnsEmptyListForInvalidJson() {
        assertEquals(emptyList<String>(), TodoExtractor.extract("not json"))
    }

    @Test
    fun returnsEmptyListWhenActionItemsMissing() {
        assertEquals(emptyList<String>(), TodoExtractor.extract("""{"summary": "ok"}"""))
        assertEquals(emptyList<String>(), TodoExtractor.extract(null))
    }

    @Test
    fun dedupesIdenticalRepeatedStrings() {
        val summary = """{"action_items": ["Water plants", " Water plants ", "Water plants"]}"""

        assertEquals(listOf("Water plants"), TodoExtractor.extract(summary))
    }
}
