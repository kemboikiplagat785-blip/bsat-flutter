package com.bsat.app

import androidx.core.app.ActivityCompat
import com.bsat.ussd.NativeLogger
import com.bsat.ussd.UssdRunner
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val LOGGER_CHANNEL = "bsat_logger"
    private val REQUEST_CALL = 1

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // LAN forwarding identity: Keystore-wrapped Ed25519 seed (main engine).
        LanIdentityKeyWrapper.register(flutterEngine.dartExecutor.binaryMessenger, applicationContext)
        LanNetworkLocks.register(flutterEngine.dartExecutor.binaryMessenger, applicationContext)

        NativeLogger.loggerMethodChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOGGER_CHANNEL)
        NativeLogger.sendLog("info", "MainActivity", "Android Engine Configured!")

        UssdRunner.requestPermissions = { permissions ->
            ActivityCompat.requestPermissions(this, permissions, REQUEST_CALL)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // The LAN listener lives in this engine; it is gone with it.
        LanNetworkLocks.release()
        NativeLogger.loggerMethodChannel = null
        UssdRunner.requestPermissions = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
