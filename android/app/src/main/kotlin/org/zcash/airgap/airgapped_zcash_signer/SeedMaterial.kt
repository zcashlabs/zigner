package org.zcash.airgap.airgapped_zcash_signer

import java.security.MessageDigest
import java.text.Normalizer
import java.util.Locale
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec

/** BIP-39 encoding and PBKDF2, using the reference English word list. No secret logging. */
internal class SeedMaterial(private val words: List<String>) {
    init { require(words.size == 2048 && words.distinct().size == 2048) }
    private val indices = words.withIndex().associate { it.value to it.index }

    fun mnemonic(entropy: ByteArray): List<String> {
        require(entropy.size in 16..32 && entropy.size % 4 == 0)
        val hash = MessageDigest.getInstance("SHA-256").digest(entropy)
        try {
            val bitCount = entropy.size * 8
            return (0 until (bitCount + bitCount / 32) / 11).map { word ->
                var index = 0
                for (offset in 0..10) {
                    val bit = word * 11 + offset
                    val value = if (bit < bitCount) {
                        (entropy[bit / 8].toInt() ushr (7 - bit % 8)) and 1
                    } else {
                        (hash[0].toInt() ushr (7 - (bit - bitCount))) and 1
                    }
                    index = (index shl 1) or value
                }
                words[index]
            }
        } finally { hash.fill(0) }
    }

    fun inspect(phrase: String): Map<String, Any> {
        require(phrase.length <= 1024) { "Recovery phrase is too long." }
        val normalized = Normalizer.normalize(phrase, Normalizer.Form.NFKD).lowercase(Locale.ROOT)
        val tokens = normalized.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
        val prefix = if (normalized.isNotEmpty() && !normalized.last().isWhitespace()) tokens.lastOrNull() ?: "" else ""
        val suggestions = if (prefix.isEmpty()) emptyList() else words.filter { it.startsWith(prefix) }.take(6)
        val valid = try { entropy(phrase).also { it.fill(0) }; true } catch (_: IllegalArgumentException) { false }
        return mapOf("count" to tokens.size, "valid" to valid, "suggestions" to suggestions)
    }

    fun questions(entropy: ByteArray, challenge: List<Int>): List<Map<String, Any>> {
        val phrase = mnemonic(entropy)
        val random = java.security.SecureRandom()
        return challenge.map { index ->
            val choices = linkedSetOf(phrase[index])
            while (choices.size < 6) choices.add(words[random.nextInt(words.size)])
            val shuffled = choices.toMutableList().also { java.util.Collections.shuffle(it, random) }
            mapOf("index" to index, "choices" to shuffled)
        }
    }

    fun entropy(phrase: String): ByteArray {
        require(phrase.length <= 1024) { "Recovery phrase is too long." }
        val normalized = Normalizer.normalize(phrase, Normalizer.Form.NFKD)
            .trim().lowercase(Locale.ROOT).split(Regex("\\s+"))
        require(normalized.size in listOf(12, 15, 18, 21, 24)) {
            "Enter 12, 15, 18, 21, or 24 recovery words."
        }
        val values = normalized.map { indices[it] ?: throw IllegalArgumentException(
            "Use the English BIP-39 word list. Check each recovery word."
        ) }
        val entropy = ByteArray(normalized.size * 4 / 3)
        for (bit in 0 until entropy.size * 8) {
            val value = (values[bit / 11] ushr (10 - bit % 11)) and 1
            entropy[bit / 8] = (entropy[bit / 8].toInt() or (value shl (7 - bit % 8))).toByte()
        }
        if (mnemonic(entropy) != normalized) {
            entropy.fill(0)
            throw IllegalArgumentException("Recovery phrase checksum is invalid. Check the words and their order.")
        }
        return entropy
    }

    // The vault encrypts entropy + optional NFKD BIP-39 passphrase, never a plaintext phrase file.
    fun pack(entropy: ByteArray, passphrase: String): ByteArray {
        require(passphrase.length <= 256) { "Passphrase must be at most 256 characters." }
        val pass = Normalizer.normalize(passphrase, Normalizer.Form.NFKD).toByteArray(Charsets.UTF_8)
        return try {
            require(pass.size <= 1024) { "The normalized passphrase is too long." }
            ByteArray(1 + entropy.size + pass.size).also {
                it[0] = entropy.size.toByte()
                entropy.copyInto(it, 1)
                pass.copyInto(it, 1 + entropy.size)
            }
        }
        finally { pass.fill(0) }
    }

    fun seed(payload: ByteArray): ByteArray {
        require(payload.isNotEmpty()) { "Invalid signer data." }
        val size = payload[0].toInt() and 255
        require(size in 16..32 && size % 4 == 0 && payload.size >= size + 1) {
            "Invalid signer data."
        }
        val entropy = payload.copyOfRange(1, size + 1)
        val phrase = try { mnemonic(entropy).joinToString(" ").toCharArray() }
        finally { entropy.fill(0) }
        val salt = ByteArray(8 + payload.size - size - 1)
        "mnemonic".toByteArray(Charsets.UTF_8).copyInto(salt)
        payload.copyInto(salt, 8, size + 1)
        val spec = PBEKeySpec(phrase, salt, 2048, 512)
        return try { SecretKeyFactory.getInstance("PBKDF2WithHmacSHA512").generateSecret(spec).encoded }
        finally { spec.clearPassword(); phrase.fill('\u0000'); salt.fill(0) }
    }
}
