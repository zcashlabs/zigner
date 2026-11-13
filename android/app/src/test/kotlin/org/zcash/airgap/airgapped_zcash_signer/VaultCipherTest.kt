package org.zcash.airgap.airgapped_zcash_signer

import org.junit.Assert.*
import org.junit.Test
import java.security.AlgorithmParameters
import java.security.Key
import java.security.Provider
import java.security.SecureRandom
import java.security.spec.AlgorithmParameterSpec
import javax.crypto.Cipher
import javax.crypto.CipherSpi
import javax.crypto.KeyGenerator

class VaultCipherTest {
    private class Trace {
        var authorized = false
        val events = mutableListOf<String>()
        var aad: ByteArray? = null
    }

    // Model Android's auth-per-use operation: init is allowed, but AAD and data
    // cannot be submitted until BiometricPrompt has authorized this exact cipher.
    private class AuthPerUseSpi(private val trace: Trace) : CipherSpi() {
        override fun engineSetMode(mode: String) {}
        override fun engineSetPadding(padding: String) {}
        override fun engineGetBlockSize() = 16
        override fun engineGetOutputSize(inputLen: Int) = inputLen
        override fun engineGetIV() = ByteArray(12)
        override fun engineGetParameters(): AlgorithmParameters? = null
        override fun engineInit(opmode: Int, key: Key, random: SecureRandom?) { trace.events.add("init:$opmode") }
        override fun engineInit(opmode: Int, key: Key, params: AlgorithmParameterSpec?, random: SecureRandom?) = engineInit(opmode, key, random)
        override fun engineInit(opmode: Int, key: Key, params: AlgorithmParameters?, random: SecureRandom?) = engineInit(opmode, key, random)
        override fun engineUpdate(input: ByteArray, inputOffset: Int, inputLen: Int): ByteArray = error("Unexpected data update")
        override fun engineUpdate(input: ByteArray, inputOffset: Int, inputLen: Int, output: ByteArray, outputOffset: Int): Int = error("Unexpected data update")
        override fun engineUpdateAAD(src: ByteArray, offset: Int, len: Int) {
            check(trace.authorized) { "KEY_USER_NOT_AUTHENTICATED" }
            trace.events.add("aad")
            trace.aad = src.copyOfRange(offset, offset + len)
        }
        override fun engineDoFinal(input: ByteArray, inputOffset: Int, inputLen: Int): ByteArray {
            check(trace.authorized)
            assertEquals("aad", trace.events.last())
            trace.events.add("finish")
            return input.copyOfRange(inputOffset, inputOffset + inputLen)
        }
        override fun engineDoFinal(input: ByteArray, inputOffset: Int, inputLen: Int, output: ByteArray, outputOffset: Int): Int = error("Unexpected output overload")
    }
    @Suppress("DEPRECATION")
    private class AuthPerUseCipher(trace: Trace) : Cipher(AuthPerUseSpi(trace), object : Provider("VaultOrderTest", 1.0, "Test-only auth ordering") {}, "AES/GCM/NoPadding")

    @Test fun encryptionAndDecryptionDeferAllAuthenticatedDataUntilAuthorization() {
        val key = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
        for (mode in listOf(Cipher.ENCRYPT_MODE, Cipher.DECRYPT_MODE)) {
            val trace = Trace()
            val provided = AuthPerUseCipher(trace)
            val initialized = if (mode == Cipher.ENCRYPT_MODE) VaultCipher.encrypt(key, provided)
                else VaultCipher.decrypt(key, ByteArray(12), provided)
            assertSame(provided, initialized)
            assertEquals(listOf("init:$mode"), trace.events)
            trace.authorized = true // Successful CryptoObject callback.
            val input = byteArrayOf(1, 2, 3)
            assertArrayEquals(input, VaultCipher.completeAuthorized(initialized, input))
            assertArrayEquals(VaultEnvelope.aad, trace.aad)
            assertEquals(listOf("init:$mode", "aad", "finish"), trace.events)
        }
    }
}
