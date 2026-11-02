package com.bsat.app

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.util.concurrent.Executors
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec

class LanWrapperException(val code: String, message: String) : Exception(message)

/**
 * Wraps the LAN forwarding Ed25519 identity seed with a non-exportable
 * AES-256-GCM key held in the Android Keystore. Ported from the BSAT Local
 * Lab prototype (IdentityKeyWrapper.kt) with a BSAT-specific key alias. The
 * wrapping key never leaves the Keystore; the unwrapped seed is returned to
 * the app process while it runs.
 *
 * Wire format of a wrapped blob: iv[12] || ciphertext || tag[16].
 */
object LanIdentityKeyWrapper {
    private const val KEYSTORE = "AndroidKeyStore"
    private const val ALIAS = "bsat_lan_identity_wrap_v1"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val IV_BYTES = 12
    private const val TAG_BITS = 128
    const val CHANNEL = "com.bsat.app/lan_keystore"

    private fun keyStore(): KeyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }

    private fun existingKey(): SecretKey? = keyStore().getKey(ALIAS, null) as SecretKey?

    private fun spec(strongBox: Boolean): KeyGenParameterSpec {
        val builder = KeyGenParameterSpec.Builder(
            ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setRandomizedEncryptionRequired(true)
        if (strongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            builder.setIsStrongBoxBacked(true)
        }
        return builder.build()
    }

    private fun createKey(): SecretKey {
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                generator.init(spec(strongBox = true))
                return generator.generateKey()
            } catch (e: StrongBoxUnavailableException) {
                // No StrongBox on this device: fall back to TEE/software.
            }
        }
        generator.init(spec(strongBox = false))
        return generator.generateKey()
    }

    fun wrap(secret: ByteArray): ByteArray {
        val key = existingKey() ?: createKey()
        val cipher = Cipher.getInstance(TRANSFORMATION)
        try {
            cipher.init(Cipher.ENCRYPT_MODE, key)
        } catch (e: KeyPermanentlyInvalidatedException) {
            throw LanWrapperException("KEY_INVALIDATED", "Keystore key was invalidated")
        }
        val ciphertext = cipher.doFinal(secret)
        return cipher.iv + ciphertext
    }

    fun unwrap(blob: ByteArray): ByteArray {
        val key = existingKey()
            ?: throw LanWrapperException("KEY_MISSING", "Keystore wrapping key is missing")
        if (blob.size <= IV_BYTES + TAG_BITS / 8) {
            throw LanWrapperException("UNWRAP_FAILED", "Wrapped identity is truncated")
        }
        val cipher = Cipher.getInstance(TRANSFORMATION)
        try {
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, blob, 0, IV_BYTES))
            return cipher.doFinal(blob, IV_BYTES, blob.size - IV_BYTES)
        } catch (e: KeyPermanentlyInvalidatedException) {
            throw LanWrapperException("KEY_INVALIDATED", "Keystore key was invalidated")
        } catch (e: AEADBadTagException) {
            throw LanWrapperException("UNWRAP_FAILED", "Wrapped identity failed authentication")
        }
    }

    fun protection(): String {
        val key = existingKey() ?: return "unknown"
        return try {
            val factory = SecretKeyFactory.getInstance(key.algorithm, KEYSTORE)
            val info = factory.getKeySpec(key, KeyInfo::class.java) as KeyInfo
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                when (info.securityLevel) {
                    KeyProperties.SECURITY_LEVEL_STRONGBOX -> "strongbox"
                    KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT -> "tee"
                    KeyProperties.SECURITY_LEVEL_SOFTWARE -> "software"
                    else -> "unknown"
                }
            } else {
                @Suppress("DEPRECATION")
                if (info.isInsideSecureHardware) "tee" else "software"
            }
        } catch (e: Exception) {
            "unknown"
        }
    }

    fun deleteKey() {
        keyStore().deleteEntry(ALIAS)
    }

    /**
     * Registers the channel on [messenger]. Keystore operations (especially
     * StrongBox key generation) can be slow, so they run off the UI thread.
     * Errors never include key material, only a code and the exception type.
     */
    fun register(messenger: BinaryMessenger, context: Context) {
        val executor = Executors.newSingleThreadExecutor()
        val mainHandler = Handler(Looper.getMainLooper())
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            executor.execute {
                try {
                    val value: Any = when (call.method) {
                        "wrap" -> wrap(call.arguments as ByteArray)
                        "unwrap" -> unwrap(call.arguments as ByteArray)
                        "protection" -> protection()
                        "deleteKey" -> {
                            deleteKey()
                            true
                        }
                        "noBackupDir" -> context.noBackupFilesDir.absolutePath
                        else -> {
                            mainHandler.post { result.notImplemented() }
                            return@execute
                        }
                    }
                    mainHandler.post { result.success(value) }
                } catch (e: LanWrapperException) {
                    mainHandler.post { result.error(e.code, e.message, null) }
                } catch (e: Exception) {
                    mainHandler.post {
                        result.error("KEYSTORE_UNAVAILABLE", e.javaClass.simpleName, null)
                    }
                }
            }
        }
    }
}
