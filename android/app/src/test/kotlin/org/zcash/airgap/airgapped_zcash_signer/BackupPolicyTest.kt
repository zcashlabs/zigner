package org.zcash.airgap.airgapped_zcash_signer

import org.junit.Assert.fail
import org.junit.Test

class BackupPolicyTest {
    private fun denied(operation: () -> Unit) {
        try { operation(); fail("An unverified backup was allowed outside an explicit debug skip.") }
        catch (_: IllegalStateException) { }
    }

    @Test fun skipRequiresBothDebugVariantAndDebuggableBuild() {
        BackupPolicy.requireDebugSkipAllowed("debug", true)
        for (type in listOf("release", "profile", "debug")) {
            for (debuggable in listOf(false, true)) {
                if (type == "debug" && debuggable) continue
                denied { BackupPolicy.requireDebugSkipAllowed(type, debuggable) }
            }
        }
    }

    @Test fun savingUnverifiedBackupRequiresAnExplicitSkipAndRechecksBuildIdentity() {
        BackupPolicy.requireCanSave(false, true, "debug", true)
        denied { BackupPolicy.requireCanSave(false, false, "debug", true) }
        denied { BackupPolicy.requireCanSave(false, true, "debug", false) }
        for (type in listOf("release", "profile")) {
            for (debuggable in listOf(false, true)) {
                for (skipRequested in listOf(false, true)) {
                    denied { BackupPolicy.requireCanSave(false, skipRequested, type, debuggable) }
                }
            }
        }
    }

    @Test fun verifiedBackupsCanBeSavedInEveryBuildMode() {
        for (type in listOf("debug", "profile", "release")) {
            BackupPolicy.requireCanSave(true, false, type, type == "debug")
        }
    }
}
