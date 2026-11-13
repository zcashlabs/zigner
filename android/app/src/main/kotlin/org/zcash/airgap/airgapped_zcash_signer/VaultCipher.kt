package org.zcash.airgap.airgapped_zcash_signer

import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Initializing an auth-per-use cipher is allowed before the system prompt.
 * Sending AAD or payload bytes is a protected operation and must wait for its
 * authorized CryptoObject, including on StrongBox implementations.
 */
internal object VaultCipher {
    fun encrypt(key: SecretKey, cipher: Cipher = Cipher.getInstance("AES/GCM/NoPadding")): Cipher =
        cipher.apply { init(Cipher.ENCRYPT_MODE, key) }

    fun decrypt(key: SecretKey, iv: ByteArray, cipher: Cipher = Cipher.getInstance("AES/GCM/NoPadding")): Cipher =
        cipher.apply { init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv)) }

    /** Call only inside the successful BiometricPrompt CryptoObject callback. */
    fun completeAuthorized(cipher: Cipher, input: ByteArray): ByteArray {
        cipher.updateAAD(VaultEnvelope.aad)
        return cipher.doFinal(input)
    }
}
