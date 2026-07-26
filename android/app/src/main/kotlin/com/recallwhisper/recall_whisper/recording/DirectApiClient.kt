package com.recallwhisper.recall_whisper.recording

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
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
                "text" to transcript,
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
                            .put("content", values["text"]),
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
        return mapOf(
            "model" to response.optString("model", model),
            "elapsed_ms" to (System.nanoTime() - started) / 1_000_000,
            "output" to response.getJSONArray("choices")
                .getJSONObject(0).getJSONObject("message").getString("content"),
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
        val text = (if (success) connection.inputStream else connection.errorStream)
            .bufferedReader().use { it.readText() }
        check(success) { text.ifBlank { "API error ${connection.responseCode}" } }
        connection.disconnect()
        return JSONObject(text)
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
    }
}
