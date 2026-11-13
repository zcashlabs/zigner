package org.zcash.airgap.airgapped_zcash_signer

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import android.view.MotionEvent

class MainActivity : FlutterActivity() {
    private var vault: SeedVaultChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        if (Build.VERSION.SDK_INT >= 31) window.setHideOverlayWindows(true)
        if (Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(false)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        vault = SeedVaultChannel(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "org.zcash.zigner/seed_vault")
            .setMethodCallHandler(vault)
    }

    override fun onStart() { super.onStart(); vault?.onForeground() }
    override fun onStop() { vault?.onBackground(); super.onStop() }
    override fun onDestroy() { vault?.close(); super.onDestroy() }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        if (event.flags and (MotionEvent.FLAG_WINDOW_IS_OBSCURED or MotionEvent.FLAG_WINDOW_IS_PARTIALLY_OBSCURED) != 0) return false
        return super.dispatchTouchEvent(event)
    }
}
