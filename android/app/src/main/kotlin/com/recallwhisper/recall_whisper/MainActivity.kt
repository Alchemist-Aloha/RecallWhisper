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
import com.recallwhisper.recall_whisper.recording.DebugLog
import com.recallwhisper.recall_whisper.recording.ProcessingScheduler
import com.recallwhisper.recall_whisper.recording.TodoExtractor
import com.recallwhisper.recall_whisper.recording.TodoItem
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
                            "summaryLanguage" to values.getString(
                                "summary_language",
                                "Same as transcript",
                            ),
                            "episodeGapMinutes" to values.getInt(
                                "episode_gap_minutes",
                                5,
                            ),
                            "episodeMaxMinutes" to values.getInt(
                                "episode_max_minutes",
                                30,
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
                        .putString(
                            "summary_language",
                            values["summaryLanguage"] as String,
                        )
                        .putInt(
                            "episode_gap_minutes",
                            values["episodeGapMinutes"] as Int,
                        )
                        .putInt(
                            "episode_max_minutes",
                            values["episodeMaxMinutes"] as Int,
                        )
                        .apply()
                    result.success(null)
                }
                "sync" -> {
                    ProcessingScheduler.enqueueTranscription(this, immediate = true)
                    ProcessingScheduler.enqueueSummary(this, immediate = true)
                    result.success(null)
                }
                "transcribeNow" -> {
                    enqueueOrError(
                        ProcessingScheduler.enqueueTranscription(this, immediate = true),
                        "transcription",
                        result,
                    )
                }
                "summarizeNow" -> {
                    enqueueOrError(
                        ProcessingScheduler.enqueueSummary(this, immediate = true),
                        "summarization",
                        result,
                    )
                }
                "retryTranscription", "retrySummary" -> databaseExecutor.execute {
                    val id = call.argument<String>("id")!!
                    val dao = RecorderDatabase.get(this).segments()
                    val summary = call.method == "retrySummary"
                    val configured = if (summary) {
                        ProcessingScheduler.hasSummaryConfig(this)
                    } else {
                        ProcessingScheduler.hasTranscriptionConfig(this)
                    }
                    val reset = if (!configured) {
                        0
                    } else if (summary) {
                        dao.retrySummary(id, System.currentTimeMillis())
                    } else {
                        dao.retryTranscription(id, System.currentTimeMillis())
                    }
                    val queued = reset > 0 && if (summary) {
                        ProcessingScheduler.enqueueSummary(
                            this,
                            immediate = true,
                            resubmitted = true,
                        )
                    } else {
                        ProcessingScheduler.enqueueTranscription(
                            this,
                            immediate = true,
                            resubmitted = true,
                        )
                    }
                    runOnUiThread {
                        if (queued) result.success(null) else result.error(
                            "resubmit_failed",
                            "Could not resubmit this ${if (summary) "summary" else "transcription"}. Check its state and settings.",
                            null,
                        )
                    }
                }
                "retryFailedTranscriptions", "retryFailedSummaries" ->
                    databaseExecutor.execute {
                        val summary = call.method == "retryFailedSummaries"
                        val configured = if (summary) {
                            ProcessingScheduler.hasSummaryConfig(this)
                        } else {
                            ProcessingScheduler.hasTranscriptionConfig(this)
                        }
                        if (!configured) {
                            runOnUiThread {
                                result.error(
                                    "missing_config",
                                    "Configure the ${if (summary) "summarization" else "transcription"} server first.",
                                    null,
                                )
                            }
                            return@execute
                        }
                        val dao = RecorderDatabase.get(this).segments()
                        val reset = if (summary) {
                            dao.retryFailedSummaries(System.currentTimeMillis())
                        } else {
                            dao.retryFailedTranscriptions(System.currentTimeMillis())
                        }
                        if (reset > 0) {
                            if (summary) {
                                ProcessingScheduler.enqueueSummary(
                                    this,
                                    immediate = true,
                                    resubmitted = true,
                                )
                            } else {
                                ProcessingScheduler.enqueueTranscription(
                                    this,
                                    immediate = true,
                                    resubmitted = true,
                                )
                            }
                        }
                        runOnUiThread { result.success(reset) }
                }
                "stopTranscription", "stopSummary" -> databaseExecutor.execute {
                    val summary = call.method == "stopSummary"
                    runCatching {
                        val operation = if (summary) {
                            ProcessingScheduler.stopSummary(this)
                        } else {
                            ProcessingScheduler.stopTranscription(this)
                        }
                        operation.result.get()
                        val dao = RecorderDatabase.get(this).segments()
                        if (summary) {
                            dao.stopSummary(System.currentTimeMillis())
                        } else {
                            dao.stopTranscription(System.currentTimeMillis())
                        }
                    }.onSuccess { stopped ->
                        runOnUiThread { result.success(stopped) }
                    }.onFailure { error ->
                        runOnUiThread {
                            result.error("stop_failed", error.message, null)
                        }
                    }
                }
                "processingStatus" -> databaseExecutor.execute {
                    val manager = androidx.work.WorkManager.getInstance(this)
                    val active: (String) -> Boolean = { name ->
                        manager.getWorkInfosForUniqueWork(name).get().any {
                            !it.state.isFinished
                        }
                    }
                    val transcribing = active("segment_transcription")
                    val summarizing = active("segment_summarization")
                    runOnUiThread {
                        result.success(
                            mapOf(
                                "transcribing" to transcribing,
                                "summarizing" to summarizing,
                            ),
                        )
                    }
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
                        startDocumentExport(json, "recallwhisper-export.json", "application/json", result)
                    }
                }
                "exportDocument" -> {
                    val content = call.argument<String>("content") ?: ""
                    val fileName = call.argument<String>("fileName")
                        ?: "recallwhisper-export.md"
                    val mimeType = call.argument<String>("mimeType") ?: "text/markdown"
                    runOnUiThread {
                        startDocumentExport(content, fileName, mimeType, result)
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
                "debugLogs" -> result.success(DebugLog.read(this))
                "debugClearLogs" -> {
                    DebugLog.clear(this)
                    result.success(null)
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
                "deleteEpisode" -> databaseExecutor.execute {
                    val id = call.argument<String>("id")!!
                    val dao = RecorderDatabase.get(this).segments()
                    dao.episodeSegments(id).forEach { link ->
                        dao.byId(link.segmentId)?.let {
                            java.io.File(it.filePath).delete()
                            dao.delete(link.segmentId)
                        }
                    }
                    dao.deleteEpisodeSegments(id)
                    dao.deleteEpisode(id)
                    dao.deleteOrphanTopics()
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
                            "transcriptionState" to it.transcriptionState,
                            "summaryState" to it.summaryState,
                            "transcriptionError" to it.transcriptionError,
                            "summaryError" to it.summaryError,
                        )
                    }
                    runOnUiThread { result.success(values) }
                }
                "timeline" -> databaseExecutor.execute {
                    val dao = RecorderDatabase.get(this).segments()
                    val segments = dao.recent()
                    val segmentsById = segments.associateBy { it.segmentId }
                    val links = dao.episodeSegments().groupBy { it.episodeId }
                    val linkedIds = links.values.flatten().mapTo(mutableSetOf()) { it.segmentId }
                    val episodes = dao.recentEpisodes().map { episode ->
                        mapOf(
                            "id" to episode.episodeId,
                            "isEpisode" to true,
                            "startedAt" to episode.startedAtUtcMs,
                            "endedAt" to episode.endedAtUtcMs,
                            "summary" to episode.summaryJson,
                            "summaryState" to "COMPLETE",
                            "segments" to links[episode.episodeId].orEmpty().mapNotNull {
                                segmentsById[it.segmentId]
                            }.map(::timelineSegment),
                        )
                    }
                    val pending = segments.filterNot { it.segmentId in linkedIds }.map {
                        mapOf(
                            "id" to it.segmentId,
                            "isEpisode" to false,
                            "startedAt" to it.startedAtUtcMs,
                            "endedAt" to it.endedAtUtcMs,
                            "summary" to it.summaryJson,
                            "summaryState" to it.summaryState,
                            "summaryError" to it.summaryError,
                            "segments" to listOf(timelineSegment(it)),
                        )
                    }
                    val values = (episodes + pending).sortedByDescending {
                        it["startedAt"] as Long
                    }
                    runOnUiThread { result.success(values) }
                }
                "topics" -> databaseExecutor.execute {
                    val dao = RecorderDatabase.get(this).segments()
                    val episodes = dao.recentEpisodes().groupBy { it.topicId }
                    val values = dao.recentTopics().map { topic ->
                        val topicEpisodes = episodes[topic.topicId] ?: emptyList()
                        mapOf(
                            "id" to topic.topicId,
                            "title" to topic.canonicalTitle.takeUnless {
                                it.isBlank() || it == "null"
                            }.orEmpty().ifBlank {
                                topicEpisodes.firstOrNull()?.localTitle
                                    ?.takeUnless { it.isBlank() || it == "null" }
                                    ?: "Topic episode"
                            },
                            "description" to topic.description,
                            "currentSummary" to topic.currentSummary,
                            "topicPath" to topic.topicPathJson,
                            "firstSeen" to topic.firstSeenUtcMs,
                            "lastSeen" to topic.lastSeenUtcMs,
                            "episodes" to topicEpisodes.map {
                                mapOf(
                                    "id" to it.episodeId,
                                    "startedAt" to it.startedAtUtcMs,
                                    "endedAt" to it.endedAtUtcMs,
                                    "title" to it.localTitle,
                                    "summary" to it.summaryJson,
                                    "keywords" to it.keywordsJson,
                                    "secondaryTopics" to it.secondaryTopicsJson,
                                    "status" to it.segmentationStatus,
                                )
                            },
                        )
                    }
                    runOnUiThread { result.success(values) }
                }
                "todos" -> databaseExecutor.execute {
                    val values = RecorderDatabase.get(this).segments().todos().map(::todoMap)
                    runOnUiThread { result.success(values) }
                }
                "addTodo" -> databaseExecutor.execute {
                    val dao = RecorderDatabase.get(this).segments()
                    val text = ((call.arguments as Map<*, *>)["text"] as String).trim()
                    if (!text.isBlank()) {
                        dao.insertTodo(
                            TodoItem(
                                todoId = "todo_" + java.util.UUID.randomUUID(),
                                text = text,
                                createdAtUtcMs = System.currentTimeMillis(),
                            ),
                        )
                    }
                    runOnUiThread { result.success(dao.todos().map(::todoMap)) }
                }
                "setTodoCompleted" -> databaseExecutor.execute {
                    runCatching {
                        val dao = RecorderDatabase.get(this).segments()
                        dao.setTodoCompleted(
                            call.argument<String>("id")!!,
                            call.argument<Boolean>("completed")!!,
                            System.currentTimeMillis(),
                        )
                        dao.todos().map(::todoMap)
                    }.onSuccess { values ->
                        runOnUiThread { result.success(values) }
                    }.onFailure { error ->
                        runOnUiThread {
                            result.error(
                                "todo_update_failed",
                                error.message ?: "Could not update this todo.",
                                null,
                            )
                        }
                    }
                }
                "deleteTodo" -> databaseExecutor.execute {
                    val dao = RecorderDatabase.get(this).segments()
                    dao.deleteTodo(call.argument<String>("id")!!)
                    runOnUiThread { result.success(dao.todos().map(::todoMap)) }
                }
                "extractTodos" -> databaseExecutor.execute {
                    val dao = RecorderDatabase.get(this).segments()
                    var inserted = 0
                    dao.recentEpisodes(Int.MAX_VALUE).forEach { episode ->
                        TodoExtractor.extract(episode.summaryJson).forEach { item ->
                            if (dao.countTodo(episode.episodeId, item) == 0) {
                                dao.insertTodo(
                                    TodoItem(
                                        todoId = "todo_" + java.util.UUID.randomUUID(),
                                        text = item,
                                        createdAtUtcMs = System.currentTimeMillis(),
                                        sourceEpisodeId = episode.episodeId,
                                        sourceTitle = episode.localTitle,
                                    ),
                                )
                                inserted += 1
                            }
                        }
                    }
                    runOnUiThread { result.success(inserted) }
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

    private fun enqueueOrError(queued: Boolean, workflow: String, result: MethodChannel.Result) {
        if (queued) result.success(null) else result.error(
            "missing_config",
            "Configure the $workflow server first.",
            null,
        )
    }

    private fun timelineSegment(
        segment: com.recallwhisper.recall_whisper.recording.CaptureSegment,
    ) = mapOf(
        "id" to segment.segmentId,
        "startedAt" to segment.startedAtUtcMs,
        "endedAt" to segment.endedAtUtcMs,
        "transcript" to segment.transcriptText,
        "transcriptionState" to segment.transcriptionState,
        "transcriptionError" to segment.transcriptionError,
    )

    private fun todoMap(it: TodoItem) = mapOf(
        "id" to it.todoId,
        "text" to it.text,
        "completed" to it.completed,
        "createdAt" to it.createdAtUtcMs,
        "completedAt" to it.completedAtUtcMs,
        "sourceEpisodeId" to it.sourceEpisodeId,
        "sourceTitle" to it.sourceTitle,
    )

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
        val dao = RecorderDatabase.get(this).segments()
        return DataExporter.toJson(
            dao.all(),
            System.currentTimeMillis(),
            dao.recentTopics(Int.MAX_VALUE),
            dao.recentEpisodes(Int.MAX_VALUE),
        )
    }

    private fun startDocumentExport(
        content: String,
        fileName: String,
        mimeType: String,
        result: MethodChannel.Result,
    ) {
        pendingExport = content to result
        startActivityForResult(
            Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = mimeType
                putExtra(Intent.EXTRA_TITLE, fileName)
            },
            EXPORT_REQUEST,
        )
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
        val (content, result) = pendingExport ?: return
        pendingExport = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.error("export_cancelled", "Export was cancelled.", null)
            return
        }
        runCatching {
            contentResolver.openOutputStream(uri, "wt")!!.bufferedWriter().use {
                it.write(content)
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
