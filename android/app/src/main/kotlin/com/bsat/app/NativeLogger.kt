package com.bsat.app

import android.util.Log
import io.flutter.plugin.common.MethodChannel
import android.os.Handler
import android.os.Looper

object NativeLogger {
    var loggerMethodChannel: MethodChannel? = null
    private val handler = Handler(Looper.getMainLooper())

    fun sendLog(level: String, tag: String, message: String) {
        Log.println(if (level == "error" || level == "fatal") Log.ERROR else if (level == "warn") Log.WARN else if (level == "info") Log.INFO else Log.DEBUG, tag, message)

        val args = mapOf("level" to level, "tag" to tag, "message" to message)
        
        handler.post {
            loggerMethodChannel?.invokeMethod("logFromNative", args)
        }
    }
}
