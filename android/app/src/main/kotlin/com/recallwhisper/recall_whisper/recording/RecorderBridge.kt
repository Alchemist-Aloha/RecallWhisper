package com.recallwhisper.recall_whisper.recording

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

object RecorderBridge {
    @Volatile var state = "STOPPED"
        private set
    @Volatile var sink: EventChannel.EventSink? = null
    private val main = Handler(Looper.getMainLooper())

    fun state(value: String) {
        state = value
        emit(mapOf("type" to "state", "state" to value))
    }

    fun segment(id: String, durationMs: Long) =
        emit(mapOf("type" to "segment", "segmentId" to id, "durationMs" to durationMs))

    fun error(code: String, message: String) =
        emit(mapOf("type" to "error", "code" to code, "message" to message))

    fun playback(segmentId: String?) =
        emit(mapOf("type" to "playback", "segmentId" to segmentId))

    private fun emit(event: Map<String, Any?>) {
        main.post { sink?.success(event) }
    }
}
