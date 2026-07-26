package com.recallwhisper.recall_whisper

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.recallwhisper.recall_whisper.recording.RecorderBridge
import com.recallwhisper.recall_whisper.recording.RecorderDatabase
import com.recallwhisper.recall_whisper.recording.RecorderForegroundService
import com.recallwhisper.recall_whisper.recording.EncryptionManager
import com.recallwhisper.recall_whisper.recording.PlaybackManager
import com.recallwhisper.recall_whisper.recording.DirectApiClient
import com.recallwhisper.recall_whisper.recording.DataExporter
import com.recallwhisper.recall_whisper.recording.UploadScheduler
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val databaseExecutor = Executors.newSingleThreadExecutor()
    private val playback = PlaybackManager()
    private var pendingStart: MethodChannel.Result? = null
    private var pendingExport: Pair<String, MethodChannel.Result>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "recall_whisper/recorder",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> startRecorder(result)
                "pause" -> serviceCommand(RecorderForegroundService.ACTION_PAUSE, result)
                "stop" -> serviceCommand(RecorderForegroundService.ACTION_STOP, result)
                "status" -> result.success(mapOf("state" to RecorderBridge.state))
                "config" -> {
                    val values = getSharedPreferences("recall_whisper", MODE_PRIVATE)
                    result.success(
                        mapOf(
                            "cellular" to values.getBoolean("cellular", false),
                            "allowHttp" to values.getBoolean("allow_http", false),
                            "trailingSilenceMs" to values.getInt(
                                "conversation_pause_ms_v2",
                                30_000,
                            ),
                            "transcriptionUrl" to values.getString("transcription_url", ""),
                            "transcriptionToken" to EncryptionManager().decryptText(
                                values.getString("transcription_token", "")!!,
                                "transcription_api_token",
                            ),
                            "transcriptionModel" to values.getString(
                                "transcription_model",
                                "whisper-1",
                            ),
                            "summarizationUrl" to values.getString("summarization_url", ""),
                            "summarizationToken" to EncryptionManager().decryptText(
                                values.getString("summarization_token", "")!!,
                                "summarization_api_token",
                            ),
                            "summarizationModel" to values.getString(
                                "summarization_model",
                                "",
                            ),
                        ),
                    )
                }
                "saveConfig" -> {
                    val values = call.arguments as Map<*, *>
                    getSharedPreferences("recall_whisper", MODE_PRIVATE).edit()
                        .putBoolean("cellular", values["cellular"] as Boolean)
                        .putBoolean("allow_http", values["allowHttp"] as Boolean)
                        .putInt(
                            "conversation_pause_ms_v2",
                            values["trailingSilenceMs"] as Int,
                        )
                        .putString(
                            "transcription_url",
                            values["transcriptionUrl"] as String,
                        )
                        .putString(
                            "transcription_token",
                            EncryptionManager().encryptText(
                                values["transcriptionToken"] as String,
                                "transcription_api_token",
                            ),
                        )
                        .putString(
                            "transcription_model",
                            values["transcriptionModel"] as String,
                        )
                        .putString(
                            "summarization_url",
                            values["summarizationUrl"] as String,
                        )
                        .putString(
                            "summarization_token",
                            EncryptionManager().encryptText(
                                values["summarizationToken"] as String,
                                "summarization_api_token",
                            ),
                        )
                        .putString(
                            "summarization_model",
                            values["summarizationModel"] as String,
                        )
                        .apply()
                    result.success(null)
                }
                "sync" -> {
                    UploadScheduler.enqueue(this, immediate = true)
                    result.success(null)
                }
                "search" -> databaseExecutor.execute {
                    val values = RecorderDatabase.get(this).segments()
                        .search(call.argument<String>("query") ?: "").map {
                            mapOf(
                                "segment_id" to it.segmentId,
                                "title" to "Recording ${it.sequenceNumber}",
                                "started_at_utc_ms" to it.startedAtUtcMs,
                                "excerpt" to (it.transcriptText ?: ""),
                                "summary" to it.summaryJson,
                            )
                        }
                    runOnUiThread { result.success(values) }
                }
                "exportData" -> databaseExecutor.execute {
                    val json = exportJson()
                    runOnUiThread {
                        pendingExport = json to result
                        startActivityForResult(
                            Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "application/json"
                                putExtra(Intent.EXTRA_TITLE, "recallwhisper-export.json")
                            },
                            EXPORT_REQUEST,
                        )
                    }
                }
                "debugLoad" -> serverCall(result) {
                    val client = DirectApiClient(this)
                    mapOf(
                        "models" to client.models(),
                        "systemPrompt" to client.systemPrompt(),
                    )
                }
                "debugSavePrompt" -> serverCall(result) {
                    DirectApiClient(this).saveSystemPrompt(
                        call.argument<String>("systemPrompt")!!,
                    )
                    null
                }
                "debugChat" -> serverCall(result) {
                    DirectApiClient(this).chat(call.arguments as Map<*, *>)
                }
                "debugTranscriptionHealth" -> serverCall(result) {
                    DirectApiClient(this).transcriptionHealth()
                }
                "deleteSegment" -> databaseExecutor.execute {
                    val id = call.argument<String>("id")!!
                    val dao = RecorderDatabase.get(this).segments()
                    dao.byId(id)?.let {
                        java.io.File(it.filePath).delete()
                        dao.delete(id)
                    }
                    runOnUiThread { result.success(null) }
                }
                "playSegment" -> databaseExecutor.execute {
                    val id = call.argument<String>("id")!!
                    val segment = RecorderDatabase.get(this).segments().byId(id)
                    if (segment == null || !java.io.File(segment.filePath).exists()) {
                        runOnUiThread {
                            result.error("missing_audio", "Local audio is no longer available.", null)
                        }
                    } else {
                        runCatching { playback.play(segment) }
                            .onSuccess { runOnUiThread { result.success(null) } }
                            .onFailure { error ->
                                runOnUiThread {
                                    result.error("playback_failed", error.message, null)
                                }
                            }
                    }
                }
                "stopPlayback" -> {
                    playback.stop()
                    RecorderBridge.playback(null)
                    result.success(null)
                }
                "segments" -> databaseExecutor.execute {
                    val values = RecorderDatabase.get(this).segments().recent().map {
                        mapOf(
                            "id" to it.segmentId,
                            "startedAt" to it.startedAtUtcMs,
                            "durationMs" to it.durationMs,
                            "sizeBytes" to it.fileSizeBytes,
                            "uploadState" to it.uploadState,
                            "serverState" to it.serverState,
                            "transcript" to it.transcriptText,
                            "summary" to it.summaryJson,
                            "processingError" to it.processingError,
                        )
                    }
                    runOnUiThread { result.success(values) }
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "recall_whisper/recorder_events",
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                RecorderBridge.sink = events
                events?.success(mapOf("type" to "state", "state" to RecorderBridge.state))
            }

            override fun onCancel(arguments: Any?) {
                RecorderBridge.sink = null
            }
        })
    }

    private fun startRecorder(result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            serviceCommand(RecorderForegroundService.ACTION_START, result)
            return
        }
        pendingStart = result
        val permissions = mutableListOf(Manifest.permission.RECORD_AUDIO)
        if (Build.VERSION.SDK_INT >= 33) permissions += Manifest.permission.POST_NOTIFICATIONS
        ActivityCompat.requestPermissions(this, permissions.toTypedArray(), PERMISSION_REQUEST)
    }

    private fun serverCall(result: MethodChannel.Result, block: () -> Any?) {
        databaseExecutor.execute {
            runCatching(block)
                .onSuccess { value -> runOnUiThread { result.success(value) } }
                .onFailure { error ->
                    runOnUiThread { result.error("server_error", error.message, null) }
                }
        }
    }

    private fun exportJson(): String {
        val segments = RecorderDatabase.get(this).segments().all()
        return DataExporter.toJson(segments, System.currentTimeMillis())
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERMISSION_REQUEST) return
        val result = pendingStart ?: return
        pendingStart = null
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            serviceCommand(RecorderForegroundService.ACTION_START, result)
        } else {
            result.error("permission_denied", "Microphone permission is required.", null)
        }
    }

    @Deprecated("Uses the platform document picker callback.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != EXPORT_REQUEST) return
        val (json, result) = pendingExport ?: return
        pendingExport = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.error("export_cancelled", "Export was cancelled.", null)
            return
        }
        runCatching {
            contentResolver.openOutputStream(uri, "wt")!!.bufferedWriter().use {
                it.write(json)
            }
        }.onSuccess {
            result.success(null)
        }.onFailure { error ->
            result.error("export_failed", error.message, null)
        }
    }

    private fun serviceCommand(action: String, result: MethodChannel.Result) {
        val intent = Intent(this, RecorderForegroundService::class.java).setAction(action)
        if (action == RecorderForegroundService.ACTION_START) {
            ContextCompat.startForegroundService(this, intent)
        } else {
            startService(intent)
        }
        result.success(null)
    }

    override fun onDestroy() {
        playback.stop()
        databaseExecutor.shutdown()
        super.onDestroy()
    }

    companion object {
        private const val PERMISSION_REQUEST = 41
        private const val EXPORT_REQUEST = 42
    }
}
