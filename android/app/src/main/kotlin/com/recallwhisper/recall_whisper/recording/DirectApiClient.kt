package com.recallwhisper.recall_whisper.recording

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.util.UUID

class DirectApiClient(private val context: Context) {
    private val preferences = context.getSharedPreferences("recall_whisper", Context.MODE_PRIVATE)
    private val encryption = EncryptionManager()

    fun transcribe(audio: ByteArray): JSONObject {
        val base = endpoint("transcription_url")
        val boundary = "RecallWhisper-${UUID.randomUUID()}"
        val body = ByteArrayOutputStream().apply {
            field(boundary, "model", preferences.getString("transcription_model", "whisper-1")!!)
            field(boundary, "response_format", "verbose_json")
            field(boundary, "timestamp_granularities[]", "word")
            write("--$boundary\r\n".toByteArray())
            write("Content-Disposition: form-data; name=\"file\"; filename=\"segment.wav\"\r\n".toByteArray())
            write("Content-Type: audio/wav\r\n\r\n".toByteArray())
            write(audio)
            write("\r\n--$boundary--\r\n".toByteArray())
        }.toByteArray()
        return request(
            "$base/audio/transcriptions",
            token("transcription_token", "transcription_api_token"),
            "POST",
            body,
            "multipart/form-data; boundary=$boundary",
            300_000,
        )
    }

    fun summarize(transcript: String): String {
        val response = chat(
            mapOf(
                "text" to "${languageInstruction()}\n\n$transcript",
                "system_prompt" to systemPrompt(),
                "model" to preferences.getString("summarization_model", ""),
                "temperature" to 0.1,
                "top_p" to 1.0,
                "max_tokens" to 2000,
                "frequency_penalty" to 0.0,
                "presence_penalty" to 0.0,
                "json_mode" to true,
            ),
        )
        return response["output"] as String
    }

    fun summarizeEpisode(segments: List<CaptureSegment>, topics: List<Topic>): JSONObject {
        val candidates = JSONArray().apply {
            topics.forEach { topic ->
                put(
                    JSONObject()
                        .put("topic_id", topic.topicId)
                        .put("title", topic.canonicalTitle)
                        .put("description", topic.description)
                        .put("current_summary", topic.currentSummary),
                )
            }
        }
        val transcript = segments.joinToString("\n") {
            "[${Instant.ofEpochMilli(it.startedAtUtcMs)}–" +
                "${Instant.ofEpochMilli(it.endedAtUtcMs)}] ${it.transcriptText}"
        }
        val response = chat(
            mapOf(
                "text" to """
                    Summarize this contiguous topic episode. Link it to one supplied
                    canonical topic only when it is genuinely the same persistent
                    subject; otherwise return null.

                    Candidate canonical topics:
                    $candidates

                    Timestamped transcript:
                    $transcript

                    Return strict JSON:
                    {
                      "canonical_topic_id": "candidate id or null",
                      "canonical_title": "stable persistent subject",
                      "topic_description": "what this topic covers",
                      "topic_path": ["broad", "narrow"],
                      "local_title": "title specific to this occurrence",
                      "summary": "faithful episode summary",
                      "topic_summary": "updated cumulative understanding",
                      "keywords": [],
                      "secondary_topics": [],
                      "decisions": [],
                      "action_items": [],
                      "questions": [],
                      "uncertainties": []
                    }
                """.trimIndent(),
                "system_prompt" to "$EPISODE_PROMPT\n${languageInstruction()}" +
                    "\n\nAdditional instructions:\n${systemPrompt()}",
                "model" to preferences.getString("summarization_model", ""),
                "temperature" to 0.1,
                "top_p" to 1.0,
                "max_tokens" to 3000,
                "frequency_penalty" to 0.0,
                "presence_penalty" to 0.0,
                "json_mode" to true,
            ),
        )
        return parseSummaryObject(response["output"] as String)
    }

    fun models(): List<String> {
        val response = request(
            "${endpoint("summarization_url")}/models",
            token("summarization_token", "summarization_api_token"),
        )
        val values = response.optJSONArray("data") ?: response.optJSONArray("models") ?: JSONArray()
        return (0 until values.length()).map {
            when (val value = values.get(it)) {
                is JSONObject -> value.optString("id", value.toString())
                else -> value.toString()
            }
        }.sorted()
    }

    fun transcriptionHealth(): Map<String, Any> {
        val started = System.nanoTime()
        val response = request(
            "${endpoint("transcription_url")}/models",
            token("transcription_token", "transcription_api_token"),
        )
        val values = response.optJSONArray("data") ?: response.optJSONArray("models") ?: JSONArray()
        val models = (0 until values.length()).map {
            when (val value = values.get(it)) {
                is JSONObject -> value.optString("id", value.toString())
                else -> value.toString()
            }
        }
        return mapOf(
            "healthy" to true,
            "elapsed_ms" to (System.nanoTime() - started) / 1_000_000,
            "models" to models,
        )
    }

    fun systemPrompt() = preferences.getString("summary_system_prompt", DEFAULT_PROMPT)!!

    fun saveSystemPrompt(value: String) {
        preferences.edit().putString("summary_system_prompt", value).apply()
    }

    private fun languageInstruction(): String {
        val language = preferences.getString(
            "summary_language",
            "Same as transcript",
        )!!.trim().ifBlank { "Same as transcript" }
        return if (language.equals("Same as transcript", ignoreCase = true)) {
            "Write all natural-language summary fields in the transcript's primary language."
        } else {
            "Write all natural-language summary fields in $language."
        }
    }

    fun chat(values: Map<*, *>): Map<String, Any?> {
        val base = endpoint("summarization_url")
        val model = (values["model"] as String).ifBlank {
            preferences.getString("summarization_model", "")!!
        }
        require(model.isNotBlank()) { "Configure a summarization model first." }
        val payload = JSONObject().apply {
            put("model", model)
            put("temperature", values["temperature"])
            put("top_p", values["top_p"])
            put("max_tokens", values["max_tokens"])
            put("frequency_penalty", values["frequency_penalty"])
            put("presence_penalty", values["presence_penalty"])
            put(
                "chat_template_kwargs",
                JSONObject().put("enable_thinking", false),
            )
            put(
                "response_format",
                JSONObject().put(
                    "type",
                    if (values["json_mode"] == true) "json_object" else "text",
                ),
            )
            put(
                "messages",
                JSONArray()
                    .put(
                        JSONObject()
                            .put("role", "system")
                            .put("content", values["system_prompt"]),
                    )
                    .put(
                        JSONObject()
                            .put("role", "user")
                            .put("content", "${values["text"]}\n/no_think"),
                    ),
            )
        }
        val started = System.nanoTime()
        val response = request(
            "$base/chat/completions",
            token("summarization_token", "summarization_api_token"),
            "POST",
            payload.toString().toByteArray(),
            "application/json",
            300_000,
        )
        val choice = response.getJSONArray("choices").getJSONObject(0)
        val message = choice.getJSONObject("message")
        val output = message.optString("content").trim()
        check(output.isNotBlank()) {
            "Summarization API returned no final text " +
                "(finish_reason=${choice.optString("finish_reason", "unknown")}, " +
                "reasoning_chars=${message.optString("reasoning_content").length})."
        }
        return mapOf(
            "model" to response.optString("model", model),
            "elapsed_ms" to (System.nanoTime() - started) / 1_000_000,
            "output" to output,
        )
    }

    private fun endpoint(key: String): String {
        val value = preferences.getString(key, "")!!.trimEnd('/')
        require(value.isNotBlank()) { "Configure ${key.replace('_', ' ')} first." }
        return NetworkPolicy.requireAllowedUrl(
            value,
            preferences.getBoolean("allow_http", false),
        )
    }

    private fun token(key: String, purpose: String) =
        encryption.decryptText(preferences.getString(key, "")!!, purpose)

    private fun request(
        url: String,
        token: String,
        method: String = "GET",
        body: ByteArray? = null,
        contentType: String? = null,
        timeout: Int = 30_000,
    ): JSONObject {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = method
            connection.connectTimeout = 15_000
            connection.readTimeout = timeout
            if (token.isNotBlank()) connection.setRequestProperty("Authorization", "Bearer $token")
            if (body != null) {
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", contentType)
                connection.outputStream.use { it.write(body) }
            }
            val success = connection.responseCode in 200..299
            val stream = if (success) connection.inputStream else connection.errorStream
            val text = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
            if (!success) {
                throw ApiException(
                    connection.responseCode,
                    text.ifBlank { "API error ${connection.responseCode}" },
                )
            }
            return JSONObject(text)
        } finally {
            connection.disconnect()
        }
    }

    private fun ByteArrayOutputStream.field(boundary: String, name: String, value: String) {
        write("--$boundary\r\n".toByteArray())
        write("Content-Disposition: form-data; name=\"$name\"\r\n\r\n".toByteArray())
        write(value.toByteArray())
        write("\r\n".toByteArray())
    }

    companion object {
        const val DEFAULT_PROMPT =
            "Summarize faithfully as strict JSON with title, summary, topics, decisions, " +
                "action_items, questions, and uncertainties. Never invent facts."
        const val EPISODE_PROMPT =
            "Organize continuous personal transcripts into faithful topic episodes. " +
                "Preserve separate occurrences, timestamps, uncertainty, and recurring " +
                "canonical topics. Never invent facts or candidate topic IDs."
    }
}

internal fun parseSummaryObject(output: String): JSONObject {
    val parsed = JSONObject(cleanJson(output))
    return when (val nested = parsed.opt("json")) {
        is JSONObject -> nested
        is String -> JSONObject(cleanJson(nested))
        else -> parsed
    }
}

private fun cleanJson(value: String): String {
    val trimmed = value.trim()
    val unfenced = if (trimmed.startsWith("```")) {
        trimmed.substringAfter('\n', trimmed).substringBeforeLast("```").trim()
    } else {
        trimmed
    }
    return if (unfenced.startsWith("json", ignoreCase = true) &&
        unfenced.drop(4).trimStart().startsWith("{")
    ) {
        unfenced.drop(4).trimStart()
    } else {
        unfenced
    }
}

internal class ApiException(val status: Int, message: String) : IOException(message)
