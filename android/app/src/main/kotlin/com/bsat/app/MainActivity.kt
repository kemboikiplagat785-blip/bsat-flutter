package com.bsat.app

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.Manifest
import android.widget.Toast
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

import android.telecom.TelecomManager
import android.telephony.SubscriptionManager
import android.content.Context
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.content.ComponentName

import com.bsat.app.UssdSession
import android.util.Log

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.bsat.app"
    private val REQUEST_CALL = 1

    // UssdSession.ussdSteps = "".split("*").filter { it.isNotEmpty() && it != "#" }.toMutableList()
    // Reset step index
    // UssdSession.currentStepIndex = 1

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "runUssdSequence") {

                    if (UssdSession.ussdSteps.isNotEmpty() || UssdSession.isRunning || UssdSession.currentStepIndex > 0) {
                        // If there is an ongoing USSD session, return an error
                        Log.d("UssdSession", "USSD session already in progress. Current steps: ${UssdSession.ussdSteps}, Current index: ${UssdSession.currentStepIndex}")
                        result.success("USSD session already in progress. Please wait for it to finish.")
                        return@setMethodCallHandler
                    }

                    Log.d("UssdSession", "Starting new USSD session")

                    UssdSession.currentStepIndex = 1
                    var sequence = call.argument<String>("sequence") ?: ""
                    if (sequence.endsWith("#")) {
                        sequence = sequence.substring(0, sequence.length - 1)
                    }
                    UssdSession.ussdSteps = sequence.split("*").filter { it.isNotEmpty()}.toMutableList()
                    Log.d("UssdSession", "UssdSteps: ${UssdSession.ussdSteps}")

                    
                    val subscriptionId = call.argument<Int>("subscriptionId") ?: 0
                    val firstCode = "*${UssdSession.ussdSteps[0]}#"
                    dialUssd(firstCode, subscriptionId, result)
                    Log.d("UssdSession", "Dialing USSD code: $firstCode")
                    // Wait for AccessibilityService to send response

                    // This commented because final response isn't provided yet
                    // UssdResponseHandler.flutterResult = result
                    // Log.d("UssdSession", "Done? ${UssdResponseHandler.flutterResult}")

                    waitForUssdResponse(result)
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun dialUssd(ussdCode: String, subscriptionId: Int, result: MethodChannel.Result) {
        val encodedHash = Uri.encode("#")
        val uri = "tel:" + ussdCode.replace("#", encodedHash)
        val intent = Intent(Intent.ACTION_CALL, Uri.parse(uri))

        Log.d("UssdSession", "Dialing USSD code: $ussdCode with subscriptionId: $subscriptionId")

        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CALL_PHONE), 1)
            return
        }

        val subscriptionManager = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
        val telecomManager = getSystemService(Context.TELECOM_SERVICE) as TelecomManager

        // Find the SubscriptionInfo for the given subscriptionId
        val subscriptionInfo = subscriptionManager.activeSubscriptionInfoList
            ?.find { it.subscriptionId == subscriptionId }

        if (subscriptionInfo == null) {
            Toast.makeText(this, "Invalid subscriptionId: $subscriptionId", Toast.LENGTH_SHORT).show()
            return
        }

        // Try to find a PhoneAccountHandle that matches the SubscriptionInfo's iccId or subscriptionId
        val phoneAccountHandle = telecomManager.callCapablePhoneAccounts.find { handle ->
            // Some manufacturers use iccId, some use subscriptionId, some use both in the id
            handle.id.contains(subscriptionInfo.iccId ?: "", ignoreCase = true) ||
            handle.id.contains(subscriptionId.toString())
        }

        if (phoneAccountHandle != null) {
            intent.putExtra("android.telecom.extra.PHONE_ACCOUNT_HANDLE", phoneAccountHandle)
        } else {
            Toast.makeText(this, "Could not find SIM slot for subscriptionId: $subscriptionId", Toast.LENGTH_SHORT).show()
            return
        }
        if(!UssdSession.isRunning) {
            UssdSession.isRunning = true
        } else {
            result.success("USSD session already in progress. Added to queue")
            return
        }

        startActivity(intent)
    }


    private fun waitForUssdResponse(result: MethodChannel.Result, maxRetries: Int = 20, delayMillis: Long = 1000, currentRetry: Int = 1, somethingIsGoingOn: Boolean = false) {
        if (UssdSession.finalResponse.isNotEmpty()) {
            // If the response is ready, return it to Flutter
            val res = UssdSession.finalResponse
            UssdSession.finalResponse = "" // Reset for future requests
            UssdSession.ussdSteps.clear() // Clear the steps
            UssdSession.currentStepIndex = 0 // Reset step index
            UssdSession.isRunning = false // Reset running state
            result.success(res)
            return
        }

        if (currentRetry >= maxRetries) {
            UssdSession.finalResponse = "" // Reset for future requests
            UssdSession.ussdSteps.clear() // Clear the steps
            UssdSession.currentStepIndex = 0 // Reset step index
            UssdSession.isRunning = false // Reset running state

            return
        }

        Log.d("UssdSession", "Waiting for response... $currentRetry")

        // Schedule the next check
        android.os.Handler(mainLooper).postDelayed({
            waitForUssdResponse(result, maxRetries, delayMillis, currentRetry + 1)
        }, delayMillis)
    }
}
