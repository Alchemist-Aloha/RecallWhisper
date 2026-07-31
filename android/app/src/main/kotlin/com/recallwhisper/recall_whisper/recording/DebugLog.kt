package com.recallwhisper.recall_whisper.recording

import android.content.Context
import android.util.Log
import java.io.File
import java.time.Instant

object DebugLog {
    private const val TAG = "RecallWhisper"
    private const val MAX_ENTRIES = 200

    fun info(context: Context, message: String) = write(context, "INFO", message)

    fun error(context: Context, message: String, error: Throwable? = null) =
        write(context, "ERROR", listOfNotNull(message, error?.message).joinToString(": "))

    @Synchronized
    fun read(context: Context): String = runCatching {
        file(context).takeIf(File::exists)?.readText().orEmpty()
    }.getOrDefault("")

    @Synchronized
    fun clear(context: Context) {
        runCatching { file(context).delete() }
    }

    private fun write(context: Context, level: String, message: String) {
        val clean = message.replace('\n', ' ')
        Log.println(if (level == "ERROR") Log.ERROR else Log.INFO, TAG, clean)
        runCatching { append(file(context), "${Instant.now()} $level $clean") }
    }

    @Synchronized
    internal fun append(file: File, line: String) {
        val entries = if (file.exists()) file.readLines().toMutableList() else mutableListOf()
        entries += line
        file.writeText(entries.takeLast(MAX_ENTRIES).joinToString("\n", postfix = "\n"))
    }

    private fun file(context: Context) = File(context.filesDir, "debug.log")
}
