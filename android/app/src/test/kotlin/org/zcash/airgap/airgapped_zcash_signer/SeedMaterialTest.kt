package org.zcash.airgap.airgapped_zcash_signer

import org.junit.Assert.*
import org.junit.Test
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.spec.GCMParameterSpec

class SeedMaterialTest {
    private val material = SeedMaterial(javaClass.getResourceAsStream("/bip39_english.txt")!!
        .bufferedReader().use { it.readLines() })
    private fun bytes(hex: String) = hex.chunked(2).map { it.toInt(16).toByte() }.toByteArray()

    @Test fun referenceVectorsMatchEntropyMnemonicAndSeed() {
        // Published Trezor/python-mnemonic English vectors; reference passphrase is TREZOR.
        val vectors = javaClass.getResourceAsStream("/bip39_vectors.tsv")!!
            .bufferedReader().use { it.readLines() }
        assertEquals(24, vectors.size)
        for (line in vectors) {
            val (entropy, phrase, seed) = line.split('\t')
            assertEquals(phrase, material.mnemonic(bytes(entropy)).joinToString(" "))
            assertArrayEquals(bytes(entropy), material.entropy(phrase))
            val payload = material.pack(bytes(entropy), "TREZOR")
            try { assertArrayEquals(bytes(seed), material.seed(payload)) }
            finally { payload.fill(0) }
        }
    }

    @Test fun unicodePassphrasesUseNfkdAndPreserveSpaces() {
        val entropy = ByteArray(32)
        assertArrayEquals(material.seed(material.pack(entropy, "caf\u00e9")),
            material.seed(material.pack(entropy, "cafe\u0301")))
        assertFalse(material.seed(material.pack(entropy, "pass")).contentEquals(
            material.seed(material.pack(entropy, " pass "))))
    }

    @Test fun importsNormalizeCaseAndWhitespaceAndAcceptEveryStandardLength() {
        for (size in listOf(16, 20, 24, 28, 32)) {
            val entropy = ByteArray(size) { 127 }
            val phrase = material.mnemonic(entropy).joinToString("\n ").uppercase()
            assertArrayEquals(entropy, material.entropy("  $phrase  "))
        }
    }

    @Test fun invalidWordsLengthsAndChecksumsAreRejectedWithoutEchoingInput() {
        for (phrase in listOf("secret-user-word", List(12) { "abandon" }.joinToString(" "),
            List(25) { "zoo" }.joinToString(" "))) {
            try { material.entropy(phrase); fail("Invalid recovery phrase was accepted") }
            catch (e: IllegalArgumentException) { assertFalse(e.message!!.contains(phrase)) }
        }
    }

    @Test fun inspectionValidatesChecksumAndCompletesOnlyLocalDictionaryWords() {
        val phrase = material.mnemonic(ByteArray(32)).joinToString(" ")
        assertEquals(true, material.inspect(phrase)["valid"])
        assertEquals(24, material.inspect(phrase)["count"])
        assertEquals(false, material.inspect(List(12) { "abandon" }.joinToString(" "))["valid"])
        assertEquals(false, material.inspect("secret-user-word")["valid"])
        assertEquals(emptyList<String>(), material.inspect("abandon ")["suggestions"])
        val suggestions = material.inspect("ab")["suggestions"] as List<*>
        assertTrue(suggestions.isNotEmpty())
        assertTrue(suggestions.size <= 6)
        assertTrue(suggestions.all { (it as String).startsWith("ab") })
    }

    @Test fun backupQuestionsHaveExactlyOneCorrectWordAndFiveDistinctDistractors() {
        val entropy = ByteArray(32) { it.toByte() }
        val phrase = material.mnemonic(entropy)
        repeat(20) {
            val questions = material.questions(entropy, listOf(0, 11, 23))
            assertEquals(listOf(0, 11, 23), questions.map { it["index"] })
            for (q in questions) {
                val choices = q["choices"] as List<*>
                assertEquals(6, choices.size)
                assertEquals(6, choices.distinct().size)
                assertEquals(1, choices.count { it == phrase[q["index"] as Int] })
            }
        }
    }

    @Test fun encryptedEnvelopeRejectsTamperingAndWrongContext() {
        val key = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
        val plaintext = material.pack(ByteArray(32), "test passphrase")
        val encrypt = VaultCipher.encrypt(key)
        val encrypted = VaultCipher.completeAuthorized(encrypt, plaintext)
        val encoded = VaultEnvelope.encode(encrypt.iv, encrypted)
        val (iv, ciphertext) = VaultEnvelope.decode(encoded)
        fun decrypt(data: ByteArray, aad: ByteArray) = Cipher.getInstance("AES/GCM/NoPadding").run {
            init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv)); updateAAD(aad); doFinal(data)
        }
        assertArrayEquals(plaintext, VaultCipher.completeAuthorized(VaultCipher.decrypt(key, iv), ciphertext))
        ciphertext[ciphertext.lastIndex] = (ciphertext.last().toInt() xor 1).toByte()
        try { decrypt(ciphertext, VaultEnvelope.aad); fail("Tampered ciphertext accepted") }
        catch (_: AEADBadTagException) { }
        try { decrypt(VaultEnvelope.decode(encoded).second, byteArrayOf(1)); fail("Wrong context accepted") }
        catch (_: AEADBadTagException) { }
        for (bad in listOf(ByteArray(0), ByteArray(49), ByteArray(2065), encoded.copyOf(48))) {
            try { VaultEnvelope.decode(bad); fail("Invalid envelope accepted") }
            catch (_: IllegalArgumentException) { }
        }
    }

    @Test fun legacyPresenceIsDetectedFromCiphertextMetadataWithoutDecryption() {
        val keysets = setOf("__androidx_security_crypto_encrypted_prefs_key_keyset__",
            "__androidx_security_crypto_encrypted_prefs_value_keyset__")
        assertFalse(LegacyStorage.hasRecord(emptySet()))
        assertFalse(LegacyStorage.hasRecord(keysets))
        assertTrue(LegacyStorage.hasRecord(keysets + "opaque-encrypted-record-name"))
        assertTrue(LegacyStorage.hasRecord(setOf(
            "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIHNlY3VyZSBzdG9yYWdlCg_zcash_testnet_mnemonic_v1")))
    }
}
