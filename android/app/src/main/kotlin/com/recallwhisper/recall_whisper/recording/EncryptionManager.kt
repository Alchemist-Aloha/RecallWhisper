package com.recallwhisper.recall_whisper.recording

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.io.File
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

data class EncryptedFile(
    val file: File,
    val sha256Ciphertext: String,
    val sha256Plaintext: String,
    val wrappedKey: String,
    val wrapNonce: String,
    val fileNonce: String,
)

class EncryptionManager {
    private val wrappingKey: SecretKey
        get() {
            val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            (store.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
            return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
                .apply {
                    init(
                        KeyGenParameterSpec.Builder(
                            KEY_ALIAS,
                            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                        ).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                            .setKeySize(256)
                            .build(),
                    )
                }.generateKey()
        }

    fun encrypt(plain: File, segmentId: String): EncryptedFile {
        val dataKey = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
        val fileCipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.ENCRYPT_MODE, dataKey)
            updateAAD(segmentId.toByteArray())
        }
        val encrypted = File(plain.parentFile, "$segmentId.wav.enc")
        encrypted.writeBytes(fileCipher.doFinal(plain.readBytes()))

        val wrapCipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.ENCRYPT_MODE, wrappingKey)
            updateAAD(segmentId.toByteArray())
        }
        val wrapped = wrapCipher.doFinal(dataKey.encoded)
        val result = EncryptedFile(
            file = encrypted,
            sha256Ciphertext = sha256(encrypted.readBytes()),
            sha256Plaintext = sha256(plain.readBytes()),
            wrappedKey = encode(wrapped),
            wrapNonce = encode(wrapCipher.iv),
            fileNonce = encode(fileCipher.iv),
        )
        check(plain.delete()) { "Could not remove plaintext ${plain.name}" }
        return result
    }

    fun decrypt(segment: CaptureSegment): ByteArray {
        require(segment.encryptionVersion == 1)
        val unwrap = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(
                Cipher.DECRYPT_MODE,
                wrappingKey,
                GCMParameterSpec(128, decode(segment.wrapNonce!!)),
            )
            updateAAD(segment.segmentId.toByteArray())
        }
        val key = SecretKeySpec(unwrap.doFinal(decode(segment.wrappedKey!!)), "AES")
        return Cipher.getInstance("AES/GCM/NoPadding").run {
            init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, decode(segment.fileNonce!!)))
            updateAAD(segment.segmentId.toByteArray())
            doFinal(File(segment.filePath).readBytes())
        }
    }

    fun encryptText(value: String, purpose: String): String {
        if (value.isEmpty()) return ""
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.ENCRYPT_MODE, wrappingKey)
            updateAAD(purpose.toByteArray())
        }
        return "${encode(cipher.iv)}:${encode(cipher.doFinal(value.toByteArray()))}"
    }

    fun decryptText(value: String, purpose: String): String {
        if (value.isEmpty() || ':' !in value) return value
        val (nonce, ciphertext) = value.split(':', limit = 2)
        return Cipher.getInstance("AES/GCM/NoPadding").run {
            init(Cipher.DECRYPT_MODE, wrappingKey, GCMParameterSpec(128, decode(nonce)))
            updateAAD(purpose.toByteArray())
            String(doFinal(decode(ciphertext)))
        }
    }

    private fun encode(value: ByteArray) = Base64.encodeToString(value, Base64.NO_WRAP)
    private fun decode(value: String) = Base64.decode(value, Base64.NO_WRAP)
    private fun sha256(value: ByteArray) = MessageDigest.getInstance("SHA-256")
        .digest(value).joinToString("") { "%02x".format(it) }

    companion object {
        private const val KEY_ALIAS = "recall_whisper_segment_wrapping_v1"
    }
}
