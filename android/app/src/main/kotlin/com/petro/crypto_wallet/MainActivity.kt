package com.petro.crypto_wallet

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Extends FlutterFragmentActivity (not FlutterActivity) because the biometric
// prompt (androidx.biometric) needs a FragmentActivity to show itself.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Block screenshots and the app-switcher preview so the recovery phrase
        // and PIN can never leak into another app's image capture.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The wallet password, kept behind the fingerprint by the Keystore.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BoundSecret.CHANNEL)
            .setMethodCallHandler(BoundSecret(this))
    }
}
