package com.recallwhisper.recall_whisper.recording

import org.json.JSONObject

internal object TodoExtractor {
    private val KEYS = listOf("text", "task", "description")

    fun extract(summaryJson: String?): List<String> {
        if (summaryJson.isNullOrBlank()) return emptyList()
        val items = runCatching {
            JSONObject(summaryJson).optJSONArray("action_items")
        }.getOrNull() ?: return emptyList()
        val todos = mutableListOf<String>()
        for (index in 0 until items.length()) {
            val raw = when (val item = items.opt(index)) {
                is String -> item
                is JSONObject -> KEYS.firstNotNullOfOrNull { key ->
                    item.optString(key).trim().takeUnless { it.isBlank() || it == "null" }
                } ?: continue
                else -> continue
            }
            val text = raw.trim().takeUnless { it.isBlank() || it == "null" } ?: continue
            todos += text
        }
        return todos.distinct()
    }
}
