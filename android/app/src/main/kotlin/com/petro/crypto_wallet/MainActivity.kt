package com.petro.crypto_wallet

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity

// Extends FlutterFragmentActivity (not FlutterActivity) because `local_auth`
// needs a FragmentActivity to show the biometric prompt.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Block screenshots and the app-switcher preview so the recovery phrase
        // and PIN can never leak into another app's image capture.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}
