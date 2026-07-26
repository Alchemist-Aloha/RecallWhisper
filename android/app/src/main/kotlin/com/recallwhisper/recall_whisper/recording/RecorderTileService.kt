package com.recallwhisper.recall_whisper.recording

import android.content.Intent
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.core.content.ContextCompat

class RecorderTileService : TileService() {
    override fun onStartListening() = update()

    override fun onClick() {
        val active = RecorderBridge.state == "LISTENING" || RecorderBridge.state == "RECORDING"
        val action = if (active) RecorderForegroundService.ACTION_PAUSE
        else RecorderForegroundService.ACTION_RESUME
        val intent = Intent(this, RecorderForegroundService::class.java).setAction(action)
        if (active) startService(intent) else ContextCompat.startForegroundService(this, intent)
        update()
    }

    private fun update() {
        val active = RecorderBridge.state == "LISTENING" || RecorderBridge.state == "RECORDING"
        qsTile?.apply {
            state = if (active) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
            label = if (active) "RecallWhisper on" else "RecallWhisper paused"
            updateTile()
        }
    }
}
