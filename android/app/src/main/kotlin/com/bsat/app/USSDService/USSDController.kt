package com.bsat.app.USSDService

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log

object UssdController {
    private const val TAG = "UssdController"
    var isRunning = false
    private val queue = ArrayList<String>()

    // Provide a callback to Flutter when process is done or failed
    var resultCallback: ((Boolean, String) -> Unit)? = null

    fun startSession(context: Context, sequence: List<String>) {
        if (sequence.isEmpty()) return
        
        Log.d(TAG, "Starting USSD session: $sequence")
        queue.clear()
        queue.addAll(sequence)
        isRunning = true

        // The first item is the number to dial
        val ussdCode = queue.removeAt(0)
        dial(context, ussdCode)
    }

    private fun dial(context: Context, code: String) {
        val encodedHash = Uri.encode("#")
        val ussd = code.replace("#", encodedHash)
        val intent = Intent(Intent.ACTION_CALL, Uri.parse("tel:$ussd"))
        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
        context.startActivity(intent)
    }

    fun getNextInput(): String? {
        return if (queue.isNotEmpty()) queue.removeAt(0) else {
            isRunning = false
            null
        }
    }
    
    fun cancel() {
        queue.clear()
        isRunning = false
    }
}
