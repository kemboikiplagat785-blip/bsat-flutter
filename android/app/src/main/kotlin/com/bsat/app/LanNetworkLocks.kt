package com.bsat.app

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Wi-Fi and multicast locks for LAN forwarding, held while the LAN listener
 * runs with a pairing.
 *
 * - The Wi-Fi lock keeps the radio out of power-save so incoming LAN
 *   connections are not delayed or dropped with the screen off.
 * - The multicast lock lets discovery announcements (UDP broadcast) through
 *   the Wi-Fi packet filter, which many phones apply with the screen off.
 *
 * Both are non-reference-counted, so repeated acquire/release calls are safe.
 */
object LanNetworkLocks {
    const val CHANNEL = "com.bsat.app/lan_network"
    private const val TAG = "bsat:lan"

    private var wifiLock: WifiManager.WifiLock? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    fun register(messenger: BinaryMessenger, context: Context) {
        val appContext = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "acquire" -> {
                        acquire(appContext)
                        result.success(null)
                    }
                    "release" -> {
                        release()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("lan_locks", e.message, null)
            }
        }
    }

    @Synchronized
    @Suppress("DEPRECATION")
    private fun acquire(context: Context) {
        val wifi = context.getSystemService(Context.WIFI_SERVICE) as? WifiManager ?: return
        val lock = wifiLock ?: wifi.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, TAG)
            .also {
                it.setReferenceCounted(false)
                wifiLock = it
            }
        if (!lock.isHeld) lock.acquire()

        val multicast = multicastLock ?: wifi.createMulticastLock(TAG).also {
            it.setReferenceCounted(false)
            multicastLock = it
        }
        if (!multicast.isHeld) multicast.acquire()
    }

    @Synchronized
    fun release() {
        wifiLock?.let { if (it.isHeld) it.release() }
        multicastLock?.let { if (it.isHeld) it.release() }
    }
}
