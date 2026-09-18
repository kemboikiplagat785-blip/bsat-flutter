package com.bsat.app

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.os.Build
import android.Manifest
import android.widget.Toast
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingBackgroundService;

import android.telecom.TelecomManager
import android.telephony.SubscriptionManager
import android.content.Context
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.content.ComponentName

import com.bsat.app.UssdSession
import com.bsat.app.UssdPlugin
import android.util.Log

import android.os.PowerManager
import android.app.KeyguardManager
import android.view.WindowManager

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.bsat.app"
    private val LOGGER_CHANNEL = "bsat_logger"
    private val REQUEST_CALL = 1

    private var pendingResult: MethodChannel.Result? = null
    private var pendingUssdCode: String? = null
    private var pendingSubscriptionId: Int? = null

    // Wakelock to keep screen on
    private var wakeLock: PowerManager.WakeLock? = null

    // UssdSession.ussdSteps = "".split("*").filter { it.isNotEmpty() && it != "#" }.toMutableList()
    // Reset step index
    // UssdSession.currentStepIndex = 1

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        flutterEngine.plugins.add(UssdPlugin())

        NativeLogger.loggerMethodChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOGGER_CHANNEL)
        sendNativeLog("info", "MainActivity", "Android Engine Configured!")

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->


            /// args:
            ///
            ///  "sequence": String (e.g. "*123*1*2#")
            ///  "subscriptionId":  int
            ///  "acceptedProcedure": List<MAp<String, any>>
            ///  "autoSwitch": bool
            ///  "isGettingSignature": bool
            ///

            if (call.method == "runUssdSequence") {

                 Log.d("BSAT_USSD", "runUssdSequence RECEIVED from Flutter")

                 if (UssdSession.ussdSteps.isNotEmpty() || UssdSession.isRunning || UssdSession.currentStepIndex > 0) {
                    // If there is an ongoing USSD session, return an error
                    sendNativeLog(
                        "debug",
                        "UssdSession",
                        "USSD session already in progress. Current steps: ${UssdSession.ussdSteps}, Current index: ${UssdSession.currentStepIndex}"
                    )
                    result.success("USSD session already in progress. Please wait for it to finish.")
                    return@setMethodCallHandler
                }

                sendNativeLog("debug", "UssdSession", "Starting new USSD session")

                UssdSession.acceptedProcedure = listOf()

                UssdSession.acceptedProcedure =
                    call.argument<List<Map<String, Any>>>("acceptedProcedure") ?: listOf()
                UssdSession.autoSwitch = call.argument<Boolean>("autoSwitch") ?: false
                UssdSession.isGettingSignature =
                    call.argument<Boolean>("isGettingSignature") ?: false

                sendNativeLog(
                    "debug",
                    "UssdSession",
                    "Accepted Procedure: ${UssdSession.acceptedProcedure}, AutoSwitch: ${UssdSession.autoSwitch}"
                )

                UssdSession.currentStepIndex = 1
                var sequence = call.argument<String>("sequence") ?: ""
                if (sequence.endsWith("#")) {
                    sequence = sequence.substring(0, sequence.length - 1)
                }
                UssdSession.ussdSteps =
                    sequence.split("*").filter { it.isNotEmpty() }.toMutableList()
                UssdSession.usedUssdSteps.clear()
                sendNativeLog("debug", "UssdSession", "UssdSteps: ${UssdSession.ussdSteps}")

                val subscriptionId = call.argument<Int>("subscriptionId") ?: 0
                val firstCode = "*${UssdSession.ussdSteps[0]}#"
                UssdSession.ussdDialed = firstCode

                Log.d("BSAT_USSD", "About to dial: $firstCode on subscriptionId=$subscriptionId")

                if (dialUssd(firstCode, subscriptionId, result)) {
                    waitForUssdResponse(result)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_CALL) {
            val result = pendingResult ?: return
            pendingResult = null
            
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                val code = pendingUssdCode ?: ""
                val subId = pendingSubscriptionId ?: 0
                if (dialUssd(code, subId, result)) {
                    waitForUssdResponse(result)
                }
            } else {
                result.error("PERMISSION_DENIED", "Phone call and state permissions are required for USSD.", null)
                UssdSession.isRunning = false
            }
        }
    }

    private fun dialUssd(ussdCode: String, subscriptionId: Int, result: MethodChannel.Result): Boolean {
        val encodedHash = Uri.encode("#")
        val uri = "tel:" + ussdCode.replace("#", encodedHash)
        val intent = Intent(Intent.ACTION_CALL, Uri.parse(uri))

        sendNativeLog(
            "debug",
            "UssdSession",
            "Dialing USSD code: $ussdCode with subscriptionId: $subscriptionId"
        )

        val hasCallPermission = ActivityCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE) == PackageManager.PERMISSION_GRANTED
        val hasPhoneStatePermission = ActivityCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED

        if (!hasCallPermission || !hasPhoneStatePermission) {
            pendingResult = result
            pendingUssdCode = ussdCode
            pendingSubscriptionId = subscriptionId
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.CALL_PHONE, Manifest.permission.READ_PHONE_STATE),
                REQUEST_CALL
            )
            return false
        }

        val subscriptionManager = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
        val telecomManager = getSystemService(Context.TELECOM_SERVICE) as TelecomManager

        val subInfo = subscriptionManager.activeSubscriptionInfoList?.find { it.subscriptionId == subscriptionId }
        if (subInfo == null) {
            Toast.makeText(this, "Invalid subscriptionId: $subscriptionId", Toast.LENGTH_SHORT).show()
            result.error("INVALID_SUBSCRIPTION", "Invalid subscriptionId: $subscriptionId", null)
            return false
        }
        
        val slotIndex = subInfo.simSlotIndex
        sendNativeLog("debug", "UssdSession", "Found SubscriptionInfo: $subInfo (slot=$slotIndex)")

        // Find the best matching PhoneAccountHandle
        val handles = telecomManager.callCapablePhoneAccounts
        var phoneAccountHandle: PhoneAccountHandle? = null

        // 1) Try match by iccId
        val iccId = subInfo.iccId
        if (!iccId.isNullOrBlank()) {
            phoneAccountHandle = handles.firstOrNull { it.id.contains(iccId, ignoreCase = true) }
        }
        // 2) Try match by subscriptionId patterns seen on OEMs
        if (phoneAccountHandle == null) {
            val subIdStr = subscriptionId.toString()
            phoneAccountHandle = handles.firstOrNull { h ->
                h.id == subIdStr ||
                        h.id.endsWith(":$subIdStr") ||
                        h.id.contains("subId_$subIdStr")
            }
        }
        // 3) Fallback to list index == SIM slot
        if (phoneAccountHandle == null && slotIndex in handles.indices) {
            phoneAccountHandle = handles[slotIndex]
        }

        sendNativeLog("debug", "UssdSession", "Selected PhoneAccountHandle: $phoneAccountHandle")

        if (phoneAccountHandle == null) {
            Toast.makeText(this, "Could not resolve SIM for subscriptionId: $subscriptionId", Toast.LENGTH_SHORT).show()
            result.error("SIM_RESOLUTION_FAILED", "Could not resolve SIM for subscriptionId: $subscriptionId", null)
            return false
        }

        intent.putExtra("android.telephony.extra.SUBSCRIPTION_INDEX", subscriptionId)

        // Best-effort: provide all widely respected extras
        intent.putExtra(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, phoneAccountHandle)
        // intent.putExtra(SubscriptionManager.EXTRA_SUBSCRIPTION_ID, subscriptionId)
        intent.putExtra("com.android.phone.extra.slot", slotIndex)
        intent.putExtra("slot", slotIndex)
        intent.putExtra("simSlot", slotIndex)
        intent.putExtra("simSlotIndex", slotIndex)
        intent.putExtra("subscription", subscriptionId)

        if (!UssdSession.isRunning) {
            UssdSession.isRunning = true
        } else {
            sendNativeLog("debug", "UssdSession", "USSD session already in progress.")
            result.success("USSD session already in progress. Added to queue")
            return false
        }

        startActivity(intent)
        return true
    }

    fun sendNativeLog(level: String, tag: String, message: String) {
        NativeLogger.sendLog(level, tag, message)
    }

    private fun waitForUssdResponse(
        result: MethodChannel.Result,
        maxRetries: Int = 20,
        delayMillis: Long = 1000,
        currentRetry: Int = 1
    ) {
        // Helper to convert wholeConversation to List<Map<String, Any?>>
        fun buildResponseList(): List<Map<String, Any?>> {
            val list = mutableListOf<Map<String, Any?>>()
            // Preserve insertion order if possible by iterating entries
            for ((key, value) in UssdSession.wholeConversation) {
                list.add(mapOf("options" to key, "choice" to value))
            }
            return list
        }

        if (UssdSession.finalResponse.isNotEmpty()) {
            // If the response is ready, return the conversation list to Flutter
            val resList = buildResponseList()

            result.success(
                mapOf(
                    "lastresponse" to UssdSession.finalResponse,
                    "conversation" to resList
                )
            )
            UssdSession.finalResponse = "" // Reset for future requests
            UssdSession.ussdSteps.clear() // Clear the steps
            UssdSession.currentStepIndex = 0 // Reset step index
            UssdSession.isRunning = false // Reset running state
            UssdSession.wholeConversation.clear()

            // create  "lastresponse": UssdSession.finalResponse, "conversation": resList

            return
        }

        if (currentRetry >= maxRetries) {
            // Timeout: return whatever we have (possibly empty)
            val resList = buildResponseList()
            result.success(mapOf("lastresponse" to UssdSession.finalResponse, "conversation" to resList, "timeout" to true))
            resetUssdSession()
            return
        }

        // Schedule the next check
        android.os.Handler(mainLooper).postDelayed({
            waitForUssdResponse(result, maxRetries, delayMillis, currentRetry + 1)
        }, delayMillis)
    }

    private fun resetUssdSession() {
        UssdSession.finalResponse = ""
        UssdSession.ussdSteps.clear()
        UssdSession.currentStepIndex = 0
        UssdSession.isRunning = false
        UssdSession.wholeConversation.clear()
    }
}
