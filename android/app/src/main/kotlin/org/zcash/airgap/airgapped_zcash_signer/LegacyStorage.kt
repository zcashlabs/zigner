package org.zcash.airgap.airgapped_zcash_signer

internal object LegacyStorage {
    // The prototype used this plugin's default namespace and one mnemonic entry.
    const val preferences = "FlutterSecureStorage"
    private const val prefix = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIHNlY3VyZSBzdG9yYWdlCg"
    private const val keysetPrefix = "__androidx_security_crypto_"

    /** Inspect ciphertext key names only. Do not initialize or migrate the legacy plugin. */
    fun hasRecord(keys: Set<String>): Boolean =
        keys.contains("${prefix}_zcash_testnet_mnemonic_v1") ||
            (keys.any { it.startsWith(keysetPrefix) } && keys.any { !it.startsWith(keysetPrefix) })
}
