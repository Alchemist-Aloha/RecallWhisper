package com.recallwhisper.recall_whisper.recording

import java.io.File
import java.io.RandomAccessFile
import java.security.MessageDigest

class WavFile(directory: File, val id: String) : AutoCloseable {
    private val temporary = File(directory, "$id.wav.tmp")
    private val output = RandomAccessFile(temporary, "rw")
    var sampleCount = 0L
        private set

    init {
        output.setLength(0)
        output.write(ByteArray(44))
    }

    fun write(samples: ShortArray) {
        val bytes = ByteArray(samples.size * 2)
        samples.forEachIndexed { index, value ->
            bytes[index * 2] = value.toInt().toByte()
            bytes[index * 2 + 1] = (value.toInt() shr 8).toByte()
        }
        output.write(bytes)
        sampleCount += samples.size
    }

    fun finish(): File {
        val dataBytes = sampleCount * 2
        output.seek(0)
        output.writeAscii("RIFF")
        output.writeIntLe((36 + dataBytes).toInt())
        output.writeAscii("WAVEfmt ")
        output.writeIntLe(16)
        output.writeShortLe(1)
        output.writeShortLe(1)
        output.writeIntLe(SileroVad.SAMPLE_RATE)
        output.writeIntLe(SileroVad.SAMPLE_RATE * 2)
        output.writeShortLe(2)
        output.writeShortLe(16)
        output.writeAscii("data")
        output.writeIntLe(dataBytes.toInt())
        output.fd.sync()
        output.close()
        val completed = File(temporary.parentFile, "$id.wav")
        check(temporary.renameTo(completed)) { "Could not finalize ${temporary.name}" }
        return completed
    }

    fun abort() {
        output.close()
        temporary.delete()
    }

    override fun close() = output.close()

    private fun RandomAccessFile.writeAscii(value: String) = write(value.toByteArray(Charsets.US_ASCII))
    private fun RandomAccessFile.writeIntLe(value: Int) =
        write(byteArrayOf(value.toByte(), (value shr 8).toByte(), (value shr 16).toByte(), (value shr 24).toByte()))
    private fun RandomAccessFile.writeShortLe(value: Int) =
        write(byteArrayOf(value.toByte(), (value shr 8).toByte()))

    companion object {
        fun sha256(file: File): String {
            val digest = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { input ->
                val buffer = ByteArray(8192)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    digest.update(buffer, 0, count)
                }
            }
            return digest.digest().joinToString("") { "%02x".format(it) }
        }
    }
}
