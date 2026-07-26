package com.recallwhisper.recall_whisper.recording

import android.media.AudioAttributes
import android.media.MediaDataSource
import android.media.MediaPlayer

class PlaybackManager {
    private var player: MediaPlayer? = null
    private var source: ByteArrayMediaDataSource? = null

    @Synchronized
    fun play(segment: CaptureSegment) {
        stop()
        source = ByteArrayMediaDataSource(EncryptionManager().decrypt(segment))
        player = MediaPlayer().apply {
            setAudioAttributes(
                AudioAttributes.Builder()
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .build(),
            )
            setDataSource(source!!)
            setOnCompletionListener {
                stop()
                RecorderBridge.playback(null)
            }
            setOnErrorListener { _, _, _ ->
                stop()
                RecorderBridge.playback(null)
                true
            }
            prepare()
            start()
        }
        RecorderBridge.playback(segment.segmentId)
    }

    @Synchronized
    fun stop() {
        player?.runCatching { stop() }
        player?.release()
        player = null
        source?.close()
        source = null
    }
}

private class ByteArrayMediaDataSource(private var bytes: ByteArray?) : MediaDataSource() {
    override fun readAt(position: Long, buffer: ByteArray, offset: Int, size: Int): Int {
        val data = bytes ?: return -1
        if (position >= data.size) return -1
        val count = minOf(size, data.size - position.toInt())
        data.copyInto(buffer, offset, position.toInt(), position.toInt() + count)
        return count
    }

    override fun getSize() = bytes?.size?.toLong() ?: 0

    override fun close() {
        bytes?.fill(0)
        bytes = null
    }
}
