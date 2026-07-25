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
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val databaseExecutor = Executors.newSingleThreadExecutor()
    private var pendingStart: MethodChannel.Result? = null

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
                "segments" -> databaseExecutor.execute {
                    val values = RecorderDatabase.get(this).segments().recent().map {
                        mapOf(
                            "id" to it.segmentId,
                            "startedAt" to it.startedAtUtcMs,
                            "durationMs" to it.durationMs,
                            "sizeBytes" to it.fileSizeBytes,
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
        databaseExecutor.shutdown()
        super.onDestroy()
    }

    companion object {
        private const val PERMISSION_REQUEST = 41
    }
}
