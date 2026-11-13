package org.zcash.airgap.airgapped_zcash_signer

/** Build identity comes from Gradle, never from a Flutter/channel argument. */
internal object BackupPolicy {
    fun requireDebugSkipAllowed(buildType: String, debuggable: Boolean) {
        check(buildType == "debug" && debuggable) {
            "Skipping the backup check is available only in debug builds."
        }
    }

    fun requireCanSave(verified: Boolean, debugSkipRequested: Boolean, buildType: String, debuggable: Boolean) {
        if (verified) return
        check(debugSkipRequested) { "Confirm your offline backup before saving." }
        // Recheck at persistence, even if a skip was previously authorized.
        requireDebugSkipAllowed(buildType, debuggable)
    }
}
