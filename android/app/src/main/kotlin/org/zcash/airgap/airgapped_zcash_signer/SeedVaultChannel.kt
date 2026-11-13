package org.zcash.airgap.airgapped_zcash_signer

import android.app.KeyguardManager
import android.content.pm.PackageManager
import android.content.Intent
import android.provider.Settings
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.util.AtomicFile
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyStore
import java.security.SecureRandom
import java.util.concurrent.Executors
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory

/** All key operations run off the UI thread; every encrypt/decrypt is bound to a CryptoObject. */
internal class SeedVaultChannel(private val activity: MainActivity) : MethodChannel.MethodCallHandler {
    private val worker = Executors.newSingleThreadExecutor()
    private val store get() = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    private val file = AtomicFile(File(activity.noBackupFilesDir, "signer-v1.vault"))
    private val material = SeedMaterial(activity.resources.openRawResource(R.raw.bip39_english)
        .bufferedReader().use { it.readLines() })
    private var draft: ByteArray? = null
    private var challenge = emptyList<Int>()
    private var backupConfirmed = false
    private var debugBackupSkipped = false
    private var verifiedAnswers = 0
    private var practicing = false
    private var generated = false
    private val metadata = activity.getSharedPreferences("zigner-vault-metadata", android.content.Context.MODE_PRIVATE)
    @Volatile private var pending = false
    @Volatile private var authenticating = false
    @Volatile private var closed = false
    @Volatile private var backgrounded = false
    private var cancellation: CancellationSignal? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (pending) {
            result.error("BUSY", "Finish or cancel the Android authentication first.", null)
            return
        }
        // Reserve the operation before dispatch: a second channel call cannot race a prompt.
        pending = true
        worker.execute {
            try {
                when (call.method) {
                    "selfTestApplicationId" -> {
                        check(BuildConfig.BUILD_TYPE == "debug" && BuildConfig.DEBUG &&
                            activity.packageName == "org.zcash.airgap.airgapped_zcash_signer.vault_test") {
                            "Vault authentication tests require the isolated debug application."
                        }
                        success(result, activity.packageName)
                    }
                    "status" -> {
                        val exists = file.baseFile.exists()
                        val legacy = LegacyStorage.hasRecord(activity.getSharedPreferences(
                            LegacyStorage.preferences, android.content.Context.MODE_PRIVATE).all.keys)
                        try {
                            requireDeviceLock()
                            val info = keyInfo(key(create = !exists))
                            verifyKey(info)
                            success(result, mapOf("hasSigner" to exists, "ready" to true,
                                "protection" to protection(info), "hasLegacySigner" to legacy,
                                "backupChecked" to metadata.getBoolean("backupChecked", false),
                                "internetPermission" to (activity.checkSelfPermission(android.Manifest.permission.INTERNET) == PackageManager.PERMISSION_GRANTED)))
                        } catch (e: Exception) {
                            success(result, mapOf("hasSigner" to exists, "ready" to false,
                                "protection" to "unavailable", "error" to safeMessage(e), "hasLegacySigner" to legacy,
                                "backupChecked" to metadata.getBoolean("backupChecked", false),
                                "internetPermission" to (activity.checkSelfPermission(android.Manifest.permission.INTERNET) == PackageManager.PERMISSION_GRANTED)))
                        }
                    }
                    "generate" -> {
                        requireEmptyVault()
                        requireDeviceLock()
                        verifyKey(keyInfo(key(create = true)))
                        clearDraft()
                        val entropy = ByteArray(32).also { SecureRandom().nextBytes(it) }
                        try {
                            val words = material.mnemonic(entropy)
                            draft = material.pack(entropy, call.argument<String>("passphrase") ?: "")
                            challenge = words.indices.toMutableList().also {
                                java.util.Collections.shuffle(it, SecureRandom())
                            }.take(3).sorted()
                            generated = true
                            success(result, mapOf("words" to words, "challenge" to challenge,
                                "questions" to material.questions(entropy, challenge)))
                        } finally { entropy.fill(0) }
                    }
                    "inspectPhrase" -> success(result, material.inspect(call.argument<String>("mnemonic") ?: ""))
                    "checkBackupWord" -> {
                        val payload = draft ?: error("Your backup check expired. Start again.")
                        val index = call.argument<Int>("question") ?: -1
                        require(index == verifiedAnswers && index in challenge.indices) { "Answer the current backup question." }
                        val entropy = payload.copyOfRange(1, 1 + (payload[0].toInt() and 255))
                        try {
                            val correct = material.mnemonic(entropy)[challenge[index]] == call.argument<String>("word")
                            if (correct) verifiedAnswers++
                            val complete = verifiedAnswers == 3
                            if (complete) {
                                backupConfirmed = true
                                if (practicing) {
                                    check(metadata.edit().putBoolean("backupChecked", true).commit()) { "Could not record your backup check." }
                                    clearDraft()
                                }
                            }
                            success(result, mapOf("correct" to correct, "complete" to complete))
                        } finally { entropy.fill(0) }
                    }
                    "restartBackupCheck" -> {
                        check(generated && draft != null) { "Generate your recovery phrase first." }
                        verifiedAnswers = 0
                        backupConfirmed = false
                        debugBackupSkipped = false
                        success(result, null)
                    }
                    "skipBackupCheckForDebug" -> {
                        BackupPolicy.requireDebugSkipAllowed(BuildConfig.BUILD_TYPE, BuildConfig.DEBUG)
                        requireEmptyVault()
                        check(generated && draft != null && !practicing) { "Generate your recovery phrase first." }
                        debugBackupSkipped = true
                        success(result, null)
                    }
                    "openSecuritySettings" -> activity.runOnUiThread {
                        try { activity.startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS)); success(result, null) }
                        catch (e: Exception) { failure(result, e) }
                    }
                    "prepareImport" -> {
                        requireEmptyVault()
                        requireDeviceLock()
                        verifyKey(keyInfo(key(create = true)))
                        clearDraft()
                        val entropy = material.entropy(call.argument<String>("mnemonic") ?: "")
                        try { draft = material.pack(entropy, call.argument<String>("passphrase") ?: "") }
                        finally { entropy.fill(0) }
                        backupConfirmed = true
                        success(result, null)
                    }
                    "confirmBackup" -> {
                        val payload = draft ?: error("Generate your recovery phrase first.")
                        val entropy = payload.copyOfRange(1, 1 + (payload[0].toInt() and 255))
                        try {
                            val words = material.mnemonic(entropy)
                            val answers = call.argument<List<String>>("answers") ?: emptyList()
                            backupConfirmed = challenge.size == 3 && answers.size == 3 &&
                                challenge.indices.all { answers[it].trim().lowercase(java.util.Locale.ROOT) == words[challenge[it]] }
                            require(backupConfirmed) { "Those words do not match. Check your written backup and try again." }
                            success(result, null)
                        } finally { entropy.fill(0) }
                    }
                    "discardDraft" -> { clearDraft(); success(result, null) }
                    "save" -> {
                        requireEmptyVault()
                        BackupPolicy.requireCanSave(backupConfirmed, debugBackupSkipped, BuildConfig.BUILD_TYPE, BuildConfig.DEBUG)
                        check(draft != null) { "Your setup session expired. Start again." }
                        requireDeviceLock()
                        val key = key(create = true)
                        verifyKey(keyInfo(key))
                        val cipher = VaultCipher.encrypt(key)
                        authenticate(result, cipher, "Protect your signer") { authorized ->
                            requireEmptyVault()
                            val encrypted = VaultCipher.completeAuthorized(authorized, draft ?: error("Setup expired."))
                            val envelope = VaultEnvelope.encode(authorized.iv, encrypted)
                            val stream = file.startWrite()
                            try { stream.write(envelope); file.finishWrite(stream) }
                            catch (e: Exception) { file.failWrite(stream); throw e }
                            // Nonsecret UI metadata is never used to authorize a vault operation.
                            check(metadata.edit().putBoolean("backupChecked", generated && backupConfirmed).commit()) { "Signer saved; could not record setup details. Reopen Zigner." }
                            clearDraft()
                            null
                        }
                    }
                    "readSeed", "unlock", "practiceBackup", "erase" -> {
                        if (call.method == "erase") require(call.argument<String>("confirmation") == "erase") { "Type erase to confirm." }
                        require(file.baseFile.exists()) { "No signer is stored on this device." }
                        requireDeviceLock()
                        val key = key(create = false)
                        verifyKey(keyInfo(key))
                        // Bound reads before allocating, including corrupt/hostile local files.
                        require(file.baseFile.length() <= 2064) { "Signer vault is damaged." }
                        val (iv, encrypted) = VaultEnvelope.decode(file.readFully())
                        val cipher = VaultCipher.decrypt(key, iv)
                        authenticate(result, cipher, if (call.method == "erase") "Erase this signer" else "Unlock your signer") { authorized ->
                            val plaintext = VaultCipher.completeAuthorized(authorized, encrypted)
                            try {
                                when (call.method) {
                                    "readSeed" -> material.seed(plaintext)
                                    "unlock" -> null // Authenticate without releasing seed material to Flutter.
                                    "erase" -> {
                                        // Destroy the hardware key first. Any remaining ciphertext is unusable.
                                        store.deleteEntry(ALIAS)
                                        file.delete()
                                        metadata.edit().clear().commit()
                                        clearDraft()
                                        null
                                    }
                                    else -> {
                                        clearDraft()
                                        val size = plaintext[0].toInt() and 255
                                        require(size in 16..32 && size % 4 == 0 && plaintext.size >= size + 1) { "Invalid signer data." }
                                        val entropy = plaintext.copyOfRange(1, size + 1)
                                        try {
                                            draft = material.pack(entropy, "")
                                            practicing = true
                                            challenge = material.mnemonic(entropy).indices.toMutableList().also {
                                                java.util.Collections.shuffle(it, SecureRandom())
                                            }.take(3).sorted()
                                            mapOf("questions" to material.questions(entropy, challenge))
                                        } finally { entropy.fill(0) }
                                    }
                                }
                            } finally { plaintext.fill(0) }
                        }
                    }
                    else -> activity.runOnUiThread { pending = false; result.notImplemented() }
                }
            } catch (e: Exception) { failure(result, e) }
        }
    }

    private fun requireEmptyVault() {
        check(!file.baseFile.exists()) { "A signer already exists. It will not be overwritten." }
    }

    private fun requireDeviceLock() {
        check(activity.getSystemService(KeyguardManager::class.java).isDeviceSecure) {
            "Set a device PIN, password, or pattern in Android Settings before continuing."
        }
    }

    private fun key(create: Boolean): SecretKey {
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        check(create && !file.baseFile.exists()) {
            "The signer encryption key is unavailable. Restore from your offline backup."
        }
        fun generate(strongBox: Boolean): SecretKey {
            val spec = KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setKeySize(256)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .setUserAuthenticationRequired(true)
                .setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG or KeyProperties.AUTH_DEVICE_CREDENTIAL)
                .setIsStrongBoxBacked(strongBox)
            // Android 12–14 have documented unlocked-device-key bugs. Authentication still
            // applies on those releases; add the extra lock-state constraint on Android 15+.
            if (Build.VERSION.SDK_INT >= 35) spec.setUnlockedDeviceRequired(true)
            return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
                init(spec.build()); generateKey()
            }
        }
        val key = if (activity.packageManager.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE)) {
            try { generate(true) } catch (_: StrongBoxUnavailableException) { generate(false) }
        } else generate(false)
        try { verifyKey(keyInfo(key)) } catch (e: Exception) { store.deleteEntry(ALIAS); throw e }
        return key
    }

    private fun keyInfo(key: SecretKey): KeyInfo = SecretKeyFactory.getInstance(key.algorithm, "AndroidKeyStore")
        .getKeySpec(key, KeyInfo::class.java) as KeyInfo

    @Suppress("DEPRECATION")
    private fun verifyKey(info: KeyInfo) {
        val hardware = if (Build.VERSION.SDK_INT >= 31) {
            info.securityLevel == KeyProperties.SECURITY_LEVEL_STRONGBOX ||
                info.securityLevel == KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT
        } else info.isInsideSecureHardware
        check(hardware && info.keySize == 256 && info.isUserAuthenticationRequired &&
            info.userAuthenticationType == (KeyProperties.AUTH_BIOMETRIC_STRONG or KeyProperties.AUTH_DEVICE_CREDENTIAL) &&
            info.isUserAuthenticationRequirementEnforcedBySecureHardware &&
            info.userAuthenticationValidityDurationSeconds <= 0) {
            "This device cannot provide authenticated hardware-backed seed protection."
        }
    }

    private fun protection(info: KeyInfo): String = if (Build.VERSION.SDK_INT >= 31 &&
        info.securityLevel == KeyProperties.SECURITY_LEVEL_STRONGBOX) "strongbox" else "tee"

    private fun authenticate(result: MethodChannel.Result, cipher: Cipher, title: String, operation: (Cipher) -> Any?) {
        authenticating = true
        activity.runOnUiThread {
            if (closed) return@runOnUiThread
            if (backgrounded) {
                failure(result, IllegalStateException("Return to Zigner before unlocking your signer."))
                return@runOnUiThread
            }
            val signal = CancellationSignal()
            cancellation = signal
            try {
                BiometricPrompt.Builder(activity)
                    .setTitle(title)
                    .setSubtitle("Use your fingerprint or device screen lock")
                    .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG or BiometricManager.Authenticators.DEVICE_CREDENTIAL)
                    .setConfirmationRequired(true)
                    .build()
                    .authenticate(BiometricPrompt.CryptoObject(cipher), signal, activity.mainExecutor,
                        object : BiometricPrompt.AuthenticationCallback() {
                            override fun onAuthenticationSucceeded(auth: BiometricPrompt.AuthenticationResult) {
                                cancellation = null
                                if (closed) return
                                authenticating = false
                                worker.execute {
                                    try {
                                        val authorized = auth.cryptoObject?.cipher ?: error("Authentication did not authorize the vault.")
                                        success(result, operation(authorized))
                                    } catch (e: Exception) { failure(result, e) }
                                }
                            }
                            override fun onAuthenticationError(code: Int, message: CharSequence) {
                                cancellation = null
                                authenticating = false
                                if (closed) return
                                if (backgrounded) worker.execute { clearDraft() }
                                // Never include raw platform/crypto exceptions or secret arguments.
                                pending = false
                                result.error("AUTH_CANCELLED", "Authentication was cancelled or unavailable. Your signer has not been unlocked.", null)
                            }
                        })
            } catch (e: Exception) { failure(result, e) }
        }
    }

    private fun success(result: MethodChannel.Result, value: Any?) = activity.runOnUiThread {
        pending = false
        try { if (!closed) result.success(value) } finally { if (value is ByteArray) value.fill(0) }
    }

    private fun failure(result: MethodChannel.Result, error: Exception) = activity.runOnUiThread {
        pending = false
        authenticating = false
        if (!closed) result.error("VAULT_ERROR", safeMessage(error), null)
    }

    private fun safeMessage(error: Exception): String = when (error) {
        is KeyPermanentlyInvalidatedException -> "Android invalidated the encryption key. Restore from your offline backup."
        is AEADBadTagException -> "Signer data failed its integrity check. Restore from your offline backup."
        is IllegalArgumentException, is IllegalStateException -> error.message ?: "The signer vault is unavailable."
        else -> "The signer vault is unavailable. No signer data was replaced."
    }

    private fun clearDraft() {
        draft?.fill(0); draft = null; challenge = emptyList(); backupConfirmed = false
        debugBackupSkipped = false
        verifiedAnswers = 0; practicing = false; generated = false
    }

    fun onBackground() {
        backgrounded = true
        // A device-credential prompt can stop the Activity; preserve only its in-flight
        // operation. Otherwise abandon uncommitted setup material when leaving the app.
        if (!authenticating) worker.execute { clearDraft() }
    }

    fun onForeground() { backgrounded = false }

    fun close() {
        closed = true
        cancellation?.cancel()
        worker.execute { clearDraft() }
        worker.shutdown()
    }

    companion object { private const val ALIAS = "zigner.seed-vault.aes256.v1" }
}
