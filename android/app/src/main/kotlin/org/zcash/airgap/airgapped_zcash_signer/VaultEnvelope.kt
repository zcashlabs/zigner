package org.zcash.airgap.airgapped_zcash_signer

/** Versioned, bounded AES-GCM ciphertext envelope. Its version is also authenticated as AAD. */
internal object VaultEnvelope {
    val aad: ByteArray get() = "org.zcash.zigner/seed-vault/v1".toByteArray(Charsets.US_ASCII)
    private val header = byteArrayOf(0x5a, 0x47, 0x4e, 0x01)

    fun encode(iv: ByteArray, ciphertext: ByteArray): ByteArray {
        require(iv.size == 12 && ciphertext.size in 33..2048)
        return header + iv + ciphertext
    }

    fun decode(bytes: ByteArray): Pair<ByteArray, ByteArray> {
        require(bytes.size in 49..2064 && bytes.copyOfRange(0, 4).contentEquals(header)) {
            "Signer vault is damaged or uses an unsupported version. Restore from your offline backup."
        }
        return bytes.copyOfRange(4, 16) to bytes.copyOfRange(16, bytes.size)
    }
}
