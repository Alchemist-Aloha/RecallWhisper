package com.recallwhisper.recall_whisper.recording

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import com.recallwhisper.recall_whisper.MainActivity
import com.recallwhisper.recall_whisper.R

class RecorderForegroundService : Service() {
    private var engine: AudioCaptureEngine? = null

    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL,
                    "Ambient recorder",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Shows when RecallWhisper is using the microphone"
                    setSound(null, null)
                },
            )
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action ?: ACTION_START) {
            ACTION_START, ACTION_RESUME -> startCapture()
            ACTION_PAUSE -> pauseCapture()
            ACTION_STOP -> stopCapture()
        }
        return START_NOT_STICKY
    }

    private fun startCapture() {
        startInForeground("LISTENING")
        if (engine != null) return
        engine = AudioCaptureEngine(
            context = this,
            onState = {
                RecorderBridge.state(it)
                notify(it)
            },
            onSegment = RecorderBridge::segment,
            onError = { code, message ->
                RecorderBridge.state("ERROR")
                RecorderBridge.error(code, message)
                notify("ERROR")
                engine = null
            },
        ).also { it.start() }
    }

    private fun pauseCapture() {
        engine?.stop()
        engine = null
        RecorderBridge.state("PAUSED")
        notify("PAUSED")
    }

    private fun stopCapture() {
        engine?.stop()
        engine = null
        RecorderBridge.state("STOPPED")
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun startInForeground(state: String) {
        val notification = notification(state)
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun notify(state: String) {
        getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, notification(state))
    }

    private fun notification(state: String): Notification {
        val paused = state == "PAUSED"
        val open = PendingIntent.getActivity(
            this,
            1,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, CHANNEL)
        } else {
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("RecallWhisper · $state")
            .setContentText(
                when (state) {
                    "RECORDING" -> "Speech is being saved locally"
                    "LISTENING" -> "Listening locally; silence is not saved"
                    "PAUSED" -> "Microphone is closed"
                    else -> "Recorder needs attention"
                },
            )
            .setContentIntent(open)
            .setOngoing(!paused)
            .addAction(
                Notification.Action.Builder(
                    null,
                    if (paused) "Resume" else "Pause",
                    serviceIntent(if (paused) ACTION_RESUME else ACTION_PAUSE, 2),
                ).build(),
            )
            .addAction(
                Notification.Action.Builder(
                    null,
                    "Stop",
                    serviceIntent(ACTION_STOP, 3),
                ).build(),
            )
            .build()
    }

    private fun serviceIntent(action: String, requestCode: Int) = PendingIntent.getService(
        this,
        requestCode,
        Intent(this, RecorderForegroundService::class.java).setAction(action),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    override fun onDestroy() {
        engine?.stop()
        engine = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val ACTION_START = "recall_whisper.START"
        const val ACTION_PAUSE = "recall_whisper.PAUSE"
        const val ACTION_RESUME = "recall_whisper.RESUME"
        const val ACTION_STOP = "recall_whisper.STOP"
        private const val CHANNEL = "ambient_recorder"
        private const val NOTIFICATION_ID = 71
    }
}
