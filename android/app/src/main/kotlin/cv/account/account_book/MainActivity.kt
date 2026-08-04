package cv.account.account_book

import android.content.Context
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.hardware.fingerprint.FingerprintManager
import android.os.Build
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec

class MainActivity : FlutterActivity() {
    private val cryptoExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var biometricCancellation: CancellationSignal? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CRYPTO_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "derivePbkdf2Sha256" -> derivePbkdf2(call, result)
                    "isBiometricAvailable" -> result.success(isBiometricAvailable())
                    "isBiometricEnabled" -> result.success(isBiometricEnabled())
                    "enableBiometric" -> {
                        val vaultKey = call.argument<String>("vaultKey")
                        if (vaultKey == null) {
                            result.error("invalid_arguments", "Missing Vault Key", null)
                        } else {
                            enableBiometric(vaultKey, result)
                        }
                    }
                    "unlockWithBiometric" -> unlockWithBiometric(result)
                    "disableBiometric" -> {
                        disableBiometric()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun derivePbkdf2(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val password = call.argument<String>("password")
        val saltBase64 = call.argument<String>("salt")
        val iterations = call.argument<Int>("iterations")
        if (password == null || saltBase64 == null || iterations == null ||
            iterations < 1 || iterations > MAX_KDF_ITERATIONS
        ) {
            result.error("invalid_arguments", "Invalid PBKDF2 arguments", null)
            return
        }

        cryptoExecutor.execute {
            var spec: PBEKeySpec? = null
            var keyBytes: ByteArray? = null
            try {
                val salt = Base64.decode(saltBase64, Base64.DEFAULT)
                spec = PBEKeySpec(password.toCharArray(), salt, iterations, KEY_LENGTH_BITS)
                keyBytes = SecretKeyFactory
                    .getInstance("PBKDF2WithHmacSHA256")
                    .generateSecret(spec)
                    .encoded
                val encoded = Base64.encodeToString(keyBytes, Base64.NO_WRAP)
                mainHandler.post { result.success(encoded) }
            } catch (error: Exception) {
                mainHandler.post {
                    result.error("pbkdf2_failed", error.javaClass.simpleName, null)
                }
            } finally {
                spec?.clearPassword()
                keyBytes?.fill(0)
            }
        }
    }

    private fun isBiometricAvailable(): Boolean {
        return when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q -> {
                val manager = getSystemService(Context.BIOMETRIC_SERVICE) as BiometricManager
                manager.canAuthenticate() == BiometricManager.BIOMETRIC_SUCCESS
            }
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.P -> {
                val manager = getSystemService(Context.FINGERPRINT_SERVICE) as FingerprintManager
                manager.isHardwareDetected && manager.hasEnrolledFingerprints()
            }
            else -> false
        }
    }

    private fun isBiometricEnabled(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false
        val preferences = getSharedPreferences(BIOMETRIC_PREFERENCES, Context.MODE_PRIVATE)
        if (!preferences.contains(BIOMETRIC_IV) ||
            !preferences.contains(BIOMETRIC_CIPHERTEXT)
        ) {
            return false
        }
        return try {
            val keyStore = loadKeyStore()
            keyStore.containsAlias(BIOMETRIC_KEY_ALIAS)
        } catch (_: Exception) {
            false
        }
    }

    private fun enableBiometric(vaultKeyBase64: String, result: MethodChannel.Result) {
        if (!isBiometricAvailable() || Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            result.error("not_available", "Fingerprint authentication is unavailable", null)
            return
        }
        val decoded = try {
            Base64.decode(vaultKeyBase64, Base64.DEFAULT)
        } catch (_: IllegalArgumentException) {
            null
        }
        if (decoded == null || decoded.size != VAULT_KEY_LENGTH_BYTES) {
            decoded?.fill(0)
            result.error("invalid_arguments", "Invalid Vault Key", null)
            return
        }
        decoded.fill(0)

        try {
            disableBiometric()
            val key = generateBiometricKey()
            if (usesPerUseCryptoObject()) {
                showBiometricPrompt(
                    title = "启用指纹解锁",
                    cipher = createEncryptionCipher(key),
                    result = result,
                ) { authenticatedCipher ->
                    if (authenticatedCipher == null) {
                        disableBiometric()
                        result.error("auth_failed", "Missing authenticated cipher", null)
                    } else {
                        encryptAndStoreVaultKey(vaultKeyBase64, authenticatedCipher, result)
                    }
                }
            } else {
                showBiometricPrompt(
                    title = "启用指纹解锁",
                    cipher = null,
                    result = result,
                ) {
                    try {
                        encryptAndStoreVaultKey(
                            vaultKeyBase64,
                            createEncryptionCipher(key),
                            result,
                        )
                    } catch (error: Exception) {
                        Log.e(LOG_TAG, "Fingerprint compatibility encryption failed", error)
                        disableBiometric()
                        result.error("encryption_failed", error.javaClass.simpleName, null)
                    }
                }
            }
        } catch (error: Exception) {
            Log.e(LOG_TAG, "Fingerprint setup failed", error)
            disableBiometric()
            result.error("setup_failed", error.javaClass.simpleName, null)
        }
    }

    private fun createEncryptionCipher(key: SecretKey): Cipher {
        return Cipher.getInstance(BIOMETRIC_TRANSFORMATION).apply {
            init(Cipher.ENCRYPT_MODE, key)
            updateAAD(BIOMETRIC_ASSOCIATED_DATA)
        }
    }

    private fun encryptAndStoreVaultKey(
        vaultKeyBase64: String,
        cipher: Cipher,
        result: MethodChannel.Result,
    ) {
        val vaultKey = Base64.decode(vaultKeyBase64, Base64.DEFAULT)
        try {
            val encrypted = cipher.doFinal(vaultKey)
            val saved = getSharedPreferences(
                BIOMETRIC_PREFERENCES,
                Context.MODE_PRIVATE,
            ).edit()
                .putString(BIOMETRIC_IV, Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
                .putString(
                    BIOMETRIC_CIPHERTEXT,
                    Base64.encodeToString(encrypted, Base64.NO_WRAP),
                )
                .commit()
            encrypted.fill(0)
            if (saved) {
                result.success(null)
            } else {
                disableBiometric()
                result.error("storage_failed", "Unable to save fingerprint key", null)
            }
        } catch (error: Exception) {
            Log.e(LOG_TAG, "Fingerprint Vault Key encryption failed", error)
            disableBiometric()
            result.error("encryption_failed", error.javaClass.simpleName, null)
        } finally {
            vaultKey.fill(0)
        }
    }

    private fun unlockWithBiometric(result: MethodChannel.Result) {
        if (!isBiometricEnabled() || Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            result.error("not_configured", "Fingerprint unlock is not configured", null)
            return
        }
        val preferences = getSharedPreferences(BIOMETRIC_PREFERENCES, Context.MODE_PRIVATE)
        val iv: ByteArray
        val encrypted: ByteArray
        try {
            val encodedIv = preferences.getString(BIOMETRIC_IV, null)
                ?: throw IllegalStateException("Missing fingerprint IV")
            val encodedCiphertext = preferences.getString(BIOMETRIC_CIPHERTEXT, null)
                ?: throw IllegalStateException("Missing fingerprint ciphertext")
            iv = Base64.decode(encodedIv, Base64.DEFAULT)
            encrypted = Base64.decode(encodedCiphertext, Base64.DEFAULT)
            if (iv.isEmpty() || encrypted.isEmpty()) {
                throw IllegalStateException("Invalid fingerprint key data")
            }
        } catch (_: Exception) {
            disableBiometric()
            result.error("not_configured", "Fingerprint key data is invalid", null)
            return
        }
        try {
            val keyStore = loadKeyStore()
            val key = keyStore.getKey(BIOMETRIC_KEY_ALIAS, null) as? SecretKey
                ?: throw IllegalStateException("Missing fingerprint key")
            if (usesPerUseCryptoObject()) {
                showBiometricPrompt(
                    title = "指纹解锁账号本子",
                    cipher = createDecryptionCipher(key, iv),
                    result = result,
                ) { authenticatedCipher ->
                    if (authenticatedCipher == null) {
                        encrypted.fill(0)
                        iv.fill(0)
                        result.error("auth_failed", "Missing authenticated cipher", null)
                    } else {
                        decryptAndReturnVaultKey(authenticatedCipher, encrypted, iv, result)
                    }
                }
            } else {
                showBiometricPrompt(
                    title = "指纹解锁账号本子",
                    cipher = null,
                    result = result,
                ) {
                    try {
                        decryptAndReturnVaultKey(
                            createDecryptionCipher(key, iv),
                            encrypted,
                            iv,
                            result,
                        )
                    } catch (error: Exception) {
                        Log.e(LOG_TAG, "Fingerprint compatibility decryption failed", error)
                        encrypted.fill(0)
                        iv.fill(0)
                        disableBiometric()
                        result.error("decryption_failed", error.javaClass.simpleName, null)
                    }
                }
            }
        } catch (_: KeyPermanentlyInvalidatedException) {
            encrypted.fill(0)
            iv.fill(0)
            disableBiometric()
            result.error("key_invalidated", "Fingerprint settings changed", null)
        } catch (error: Exception) {
            Log.e(LOG_TAG, "Fingerprint unlock failed", error)
            encrypted.fill(0)
            iv.fill(0)
            result.error("unlock_failed", error.javaClass.simpleName, null)
        }
    }

    private fun createDecryptionCipher(key: SecretKey, iv: ByteArray): Cipher {
        return Cipher.getInstance(BIOMETRIC_TRANSFORMATION).apply {
            init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv))
            updateAAD(BIOMETRIC_ASSOCIATED_DATA)
        }
    }

    private fun decryptAndReturnVaultKey(
        cipher: Cipher,
        encrypted: ByteArray,
        iv: ByteArray,
        result: MethodChannel.Result,
    ) {
        var vaultKey: ByteArray? = null
        try {
            vaultKey = cipher.doFinal(encrypted)
            if (vaultKey.size != VAULT_KEY_LENGTH_BYTES) {
                throw IllegalStateException("Invalid Vault Key length")
            }
            result.success(Base64.encodeToString(vaultKey, Base64.NO_WRAP))
        } catch (error: Exception) {
            Log.e(LOG_TAG, "Fingerprint Vault Key decryption failed", error)
            disableBiometric()
            result.error("decryption_failed", error.javaClass.simpleName, null)
        } finally {
            vaultKey?.fill(0)
            encrypted.fill(0)
            iv.fill(0)
        }
    }

    private fun showBiometricPrompt(
        title: String,
        cipher: Cipher?,
        result: MethodChannel.Result,
        onAuthenticated: (Cipher?) -> Unit,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            result.error("not_available", "Fingerprint authentication is unavailable", null)
            return
        }
        biometricCancellation?.cancel()
        val cancellation = CancellationSignal()
        biometricCancellation = cancellation
        val completed = AtomicBoolean(false)
        val executor = mainExecutor
        val builder = BiometricPrompt.Builder(this)
            .setTitle(title)
            .setSubtitle("请验证已录入的指纹")
            .setNegativeButton("使用主密码", executor) { _, _ ->
                if (completed.compareAndSet(false, true)) {
                    biometricCancellation = null
                    result.error("auth_canceled", "Fingerprint authentication canceled", null)
                }
            }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setConfirmationRequired(false)
        }
        val callback = object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(
                    authenticationResult: BiometricPrompt.AuthenticationResult,
                ) {
                    if (!completed.compareAndSet(false, true)) return
                    biometricCancellation = null
                    val authenticatedCipher = authenticationResult.cryptoObject?.cipher
                    if (cipher != null && authenticatedCipher == null) {
                        result.error("auth_failed", "Missing authenticated cipher", null)
                    } else {
                        onAuthenticated(authenticatedCipher)
                    }
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    if (!completed.compareAndSet(false, true)) return
                    biometricCancellation = null
                    val code = when (errorCode) {
                        BiometricPrompt.BIOMETRIC_ERROR_CANCELED,
                        BiometricPrompt.BIOMETRIC_ERROR_USER_CANCELED -> "auth_canceled"
                        BiometricPrompt.BIOMETRIC_ERROR_LOCKOUT,
                        BiometricPrompt.BIOMETRIC_ERROR_LOCKOUT_PERMANENT -> "auth_locked"
                        else -> "auth_failed"
                    }
                    result.error(code, errString.toString(), null)
                }
            }
        val prompt = builder.build()
        if (cipher == null) {
            prompt.authenticate(cancellation, executor, callback)
        } else {
            prompt.authenticate(
                BiometricPrompt.CryptoObject(cipher),
                cancellation,
                executor,
                callback,
            )
        }
    }

    private fun generateBiometricKey(): SecretKey {
        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            ANDROID_KEY_STORE,
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                BIOMETRIC_KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setUserAuthenticationRequired(true)
                .setUserAuthenticationValidityDurationSeconds(
                    if (usesPerUseCryptoObject()) -1 else BIOMETRIC_AUTH_VALIDITY_SECONDS,
                )
                .setInvalidatedByBiometricEnrollment(true)
                .build(),
        )
        return generator.generateKey()
    }

    private fun loadKeyStore(): KeyStore {
        return KeyStore.getInstance(ANDROID_KEY_STORE).apply { load(null) }
    }

    private fun usesPerUseCryptoObject(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
    }

    private fun disableBiometric() {
        biometricCancellation?.cancel()
        biometricCancellation = null
        getSharedPreferences(BIOMETRIC_PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .clear()
            .commit()
        try {
            val keyStore = loadKeyStore()
            if (keyStore.containsAlias(BIOMETRIC_KEY_ALIAS)) {
                keyStore.deleteEntry(BIOMETRIC_KEY_ALIAS)
            }
        } catch (_: Exception) {
            // The stored blob is already gone, so master-password fallback remains safe.
        }
    }

    override fun onDestroy() {
        biometricCancellation?.cancel()
        cryptoExecutor.shutdownNow()
        super.onDestroy()
    }

    companion object {
        private const val CRYPTO_CHANNEL = "account_book/crypto"
        private const val KEY_LENGTH_BITS = 256
        private const val MAX_KDF_ITERATIONS = 2_000_000
        private const val LOG_TAG = "AccountBookBiometric"
        private const val ANDROID_KEY_STORE = "AndroidKeyStore"
        private const val BIOMETRIC_KEY_ALIAS = "account_book_biometric_vault_key_v1"
        private const val BIOMETRIC_PREFERENCES = "biometric_vault"
        private const val BIOMETRIC_IV = "iv"
        private const val BIOMETRIC_CIPHERTEXT = "ciphertext"
        private const val BIOMETRIC_TRANSFORMATION = "AES/GCM/NoPadding"
        private const val VAULT_KEY_LENGTH_BYTES = 32
        private const val GCM_TAG_LENGTH_BITS = 128
        private const val BIOMETRIC_AUTH_VALIDITY_SECONDS = 5
        private val BIOMETRIC_ASSOCIATED_DATA =
            "account_book:biometric_vault_key:v1".toByteArray(Charsets.UTF_8)
    }
}
