package com.petro.crypto_wallet

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Keeps one secret (the wallet password) behind the fingerprint, enforced by
 * the secure hardware rather than by the app.
 *
 * The AES-256-GCM key lives in the Android Keystore with
 * `setUserAuthenticationRequired(true)` and **no validity window**, so every
 * single use of the key needs a fresh, strong biometric authentication handed
 * over through a `BiometricPrompt.CryptoObject`. Code that merely runs inside
 * the app process — or a root shell reading app storage — cannot decrypt the
 * stored blob without the finger: the key never leaves the hardware and will
 * not operate unauthenticated. Enrolling another fingerprint invalidates the
 * key (`setInvalidatedByBiometricEnrollment`), so someone who can add their own
 * finger to a stolen, unlocked phone does not inherit access either.
 *
 * Dart side: `lib/data/wallet/secure_pin_store.dart`.
 */
class BoundSecret(private val activity: FragmentActivity) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "material_wallet/bound_secret"
        private const val KEYSTORE = "AndroidKeyStore"
        private const val ALIAS = "material_wallet_bound_secret_v1"
        private const val PREFS = "material_wallet_bound_secret"
        private const val PREF_IV = "iv"
        private const val PREF_DATA = "data"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val TAG_BITS = 128
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(status())
            "write" -> write(
                call.argument<String>("secret") ?: "",
                call.argument<String>("title") ?: "Material Wallet",
                call.argument<String>("subtitle"),
                call.argument<String>("cancel") ?: "Cancel",
                result,
            )
            "read" -> read(
                call.argument<String>("title") ?: "Material Wallet",
                call.argument<String>("subtitle"),
                call.argument<String>("cancel") ?: "Cancel",
                result,
            )
            "clear" -> {
                clear()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun status(): String =
        when (BiometricManager.from(activity)
            .canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG)) {
            BiometricManager.BIOMETRIC_SUCCESS -> "ok"
            BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> "none_enrolled"
            BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE -> "no_hardware"
            else -> "unavailable"
        }

    private fun prefs() = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun keyStore(): KeyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }

    private fun clear() {
        try {
            val store = keyStore()
            if (store.containsAlias(ALIAS)) store.deleteEntry(ALIAS)
        } catch (_: Exception) {
            // Nothing to delete, or the keystore is unavailable: the blob below
            // is useless without the key either way.
        }
        prefs().edit().clear().apply()
    }

    /** A brand new key every time a secret is stored, so an old blob can never be reused. */
    private fun createKey(): SecretKey {
        clear()
        val spec = KeyGenParameterSpec.Builder(
            ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)
            .apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    // Timeout 0 = authentication is needed for every operation.
                    setUserAuthenticationParameters(
                        0,
                        KeyProperties.AUTH_BIOMETRIC_STRONG,
                    )
                } else {
                    @Suppress("DEPRECATION")
                    setUserAuthenticationValidityDurationSeconds(-1)
                }
            }
            .build()
        val generator =
            KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(spec)
        return generator.generateKey()
    }

    private fun write(
        secret: String,
        title: String,
        subtitle: String?,
        cancel: String,
        result: MethodChannel.Result,
    ) {
        if (secret.isEmpty()) {
            result.error("error", "Nothing to store.", null)
            return
        }
        val cipher: Cipher
        try {
            cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, createKey())
        } catch (e: Exception) {
            clear()
            result.error("unavailable", e.message, null)
            return
        }
        prompt(cipher, title, subtitle, cancel, result) { authed ->
            val sealed = authed.doFinal(secret.toByteArray(Charsets.UTF_8))
            prefs().edit()
                .putString(PREF_IV, Base64.encodeToString(authed.iv, Base64.NO_WRAP))
                .putString(PREF_DATA, Base64.encodeToString(sealed, Base64.NO_WRAP))
                .apply()
            true
        }
    }

    private fun read(
        title: String,
        subtitle: String?,
        cancel: String,
        result: MethodChannel.Result,
    ) {
        val iv = prefs().getString(PREF_IV, null)
        val data = prefs().getString(PREF_DATA, null)
        if (iv == null || data == null) {
            result.error("invalidated", "Nothing is stored.", null)
            return
        }
        val cipher: Cipher
        try {
            val key = keyStore().getKey(ALIAS, null) as SecretKey?
            if (key == null) {
                clear()
                result.error("invalidated", "The key is gone.", null)
                return
            }
            cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(
                Cipher.DECRYPT_MODE,
                key,
                GCMParameterSpec(TAG_BITS, Base64.decode(iv, Base64.NO_WRAP)),
            )
        } catch (e: KeyPermanentlyInvalidatedException) {
            // A fingerprint was added or removed: the hardware key is dead.
            clear()
            result.error("invalidated", "Biometrics changed.", null)
            return
        } catch (e: Exception) {
            result.error("unavailable", e.message, null)
            return
        }
        prompt(cipher, title, subtitle, cancel, result) { authed ->
            String(
                authed.doFinal(Base64.decode(data, Base64.NO_WRAP)),
                Charsets.UTF_8,
            )
        }
    }

    /**
     * Shows the system fingerprint prompt bound to [cipher]; on success runs
     * [onAuthenticated] with the now-authorised cipher and returns its result.
     */
    private fun prompt(
        cipher: Cipher,
        title: String,
        subtitle: String?,
        cancel: String,
        result: MethodChannel.Result,
        onAuthenticated: (Cipher) -> Any,
    ) {
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .apply { if (subtitle != null) setSubtitle(subtitle) }
            .setNegativeButtonText(cancel)
            // Strong only: a CryptoObject cannot be combined with the device
            // credential before Android 11, and a weak (face-only) sensor is
            // not enough to release a wallet password.
            .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
            .setConfirmationRequired(false)
            .build()

        var answered = false
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(
                authResult: BiometricPrompt.AuthenticationResult,
            ) {
                if (answered) return
                answered = true
                val authed = authResult.cryptoObject?.cipher
                if (authed == null) {
                    result.error("error", "No cipher came back from the prompt.", null)
                    return
                }
                try {
                    result.success(onAuthenticated(authed))
                } catch (e: Exception) {
                    result.error("error", e.message, null)
                }
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                if (answered) return
                answered = true
                // Cancelled, locked out, timed out…: nothing was released.
                result.error("cancelled", errString.toString(), null)
            }
            // onAuthenticationFailed (a finger that did not match) keeps the
            // prompt open; the system counts the attempts and locks out itself.
        }

        BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), callback)
            .authenticate(info, BiometricPrompt.CryptoObject(cipher))
    }
}
