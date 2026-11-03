package com.bsat.ussd

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.telephony.SubscriptionInfo
import android.telephony.SubscriptionManager
import android.widget.Toast
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayDeque

class UssdRequest(
    val sequence: String,
    val subscriptionId: Int,
    val procedure: List<SignatureMatcher.RecordedStep>,
    val autoSwitch: Boolean,
    val isGettingSignature: Boolean,
) {
    companion object {
        fun from(call: MethodCall) = UssdRequest(
            sequence = call.argument<String>("sequence") ?: "",
            subscriptionId = call.argument<Int>("subscriptionId") ?: 0,
            procedure = (call.argument<List<Map<String, Any?>>>("acceptedProcedure") ?: listOf())
                .map {
                    SignatureMatcher.RecordedStep(
                        it["options"]?.toString() ?: "",
                        it["choice"]?.toString() ?: ""
                    )
                },
            autoSwitch = call.argument<Boolean>("autoSwitch") ?: false,
            isGettingSignature = call.argument<Boolean>("isGettingSignature") ?: false,
        )
    }
}

/**
 * Dials a USSD sequence and waits for USSDResponderService to walk it. Needs
 * no screen of this app. Calls from all Flutter engines arrive here on the main
 * thread, so one queue keeps USSD sessions from overlapping across engines.
 */
object UssdRunner {
    private const val TAG = "UssdSession"
    private const val MAX_WAIT_CHECKS = 20
    private const val WAIT_CHECK_MILLIS = 1000L

    /** Longer than any session is expected to take; a recording can be long. */
    private const val MAX_SCREEN_ON_MILLIS = 3 * 60 * 1000L

    private val mainHandler = Handler(Looper.getMainLooper())
    private val queue = ArrayDeque<() -> Unit>()
    private var screenOn: PowerManager.WakeLock? = null

    /** Set while the app's screen exists, which can show a permission prompt. */
    var requestPermissions: ((Array<String>) -> Unit)? = null

    fun run(context: Context, request: UssdRequest, result: MethodChannel.Result) {
        val start = { start(context, request, result) }
        if (UssdSession.ussdSteps.isNotEmpty() || UssdSession.isRunning || UssdSession.currentStepIndex > 0) {
            NativeLogger.sendLog("debug", TAG, "USSD session active; queued request (${queue.size + 1} waiting)")
            queue.addLast(start)
        } else {
            start()
        }
    }

    private fun start(context: Context, request: UssdRequest, result: MethodChannel.Result) {
        NativeLogger.sendLog("debug", TAG, "Starting new USSD session")
        UssdSession.procedure = request.procedure
        UssdSession.autoSwitch = request.autoSwitch
        UssdSession.isGettingSignature = request.isGettingSignature
        NativeLogger.sendLog(
            "debug",
            TAG,
            "Signature steps: ${request.procedure.size}, AutoSwitch: ${request.autoSwitch}, Recording: ${request.isGettingSignature}"
        )

        UssdSession.currentStepIndex = 1
        UssdSession.ussdSteps = request.sequence.removeSuffix("#")
            .split("*").filter { it.isNotEmpty() }.toMutableList()
        UssdSession.usedUssdSteps.clear()
        NativeLogger.sendLog("debug", TAG, "UssdSteps: ${UssdSession.ussdSteps}")

        if (UssdSession.ussdSteps.isEmpty()) {
            fail(result, "EMPTY_USSD_SEQUENCE", "USSD sequence is empty. No USSD code was provided.")
            return
        }

        val firstCode = "*${UssdSession.ussdSteps[0]}#"
        UssdSession.ussdDialed = firstCode

        val missing = arrayOf(Manifest.permission.CALL_PHONE, Manifest.permission.READ_PHONE_STATE)
            .filter { context.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isNotEmpty()) {
            requestPermissions?.invoke(missing.toTypedArray())
            fail(result, "PERMISSION_DENIED", "Phone call and state permissions are required for USSD.")
            return
        }

        val subscription = activeSubscription(context, request.subscriptionId)
        if (subscription == null) {
            Toast.makeText(context, "Invalid subscriptionId: ${request.subscriptionId}", Toast.LENGTH_SHORT).show()
            fail(result, "INVALID_SUBSCRIPTION", "Invalid subscriptionId: ${request.subscriptionId}")
            return
        }
        val account = phoneAccount(context, subscription)
        if (account == null) {
            Toast.makeText(context, "Could not resolve SIM for subscriptionId: ${request.subscriptionId}", Toast.LENGTH_SHORT).show()
            fail(result, "SIM_RESOLUTION_FAILED", "Could not resolve SIM for subscriptionId: ${request.subscriptionId}")
            return
        }

        UssdSession.isRunning = true
        keepScreenOn(context)
        try {
            dial(context, firstCode, subscription, account)
        } catch (error: Exception) {
            fail(result, "USSD_START_FAILED", error.message ?: "Could not start USSD.")
            return
        }
        waitForResponse(result, 1, UssdSession.currentStepIndex)
    }

    /**
     * With the screen off Android does not show the USSD dialog, so
     * USSDResponderService never sees the reply. The screen stays on for the
     * session only.
     */
    @Suppress("DEPRECATION")
    private fun keepScreenOn(context: Context) {
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        if (power.isInteractive) return
        screenOn = power.newWakeLock(
            PowerManager.SCREEN_DIM_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
            "bsat:ussd"
        ).apply {
            setReferenceCounted(false)
            acquire(MAX_SCREEN_ON_MILLIS)
        }
    }

    private fun activeSubscription(context: Context, subscriptionId: Int): SubscriptionInfo? {
        val manager = context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
        return try {
            manager.activeSubscriptionInfoList?.find { it.subscriptionId == subscriptionId }
        } catch (_: SecurityException) {
            null
        }
    }

    private fun phoneAccount(context: Context, subscription: SubscriptionInfo): PhoneAccountHandle? {
        val telecom = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
        val handles = telecom.callCapablePhoneAccounts
        val subscriptionId = subscription.subscriptionId.toString()
        val iccId = subscription.iccId

        // By iccId; by subscriptionId patterns seen on OEMs; by SIM slot.
        val account = handles.firstOrNull { !iccId.isNullOrBlank() && it.id.contains(iccId, ignoreCase = true) }
            ?: handles.firstOrNull {
                it.id == subscriptionId || it.id.endsWith(":$subscriptionId") || it.id.contains("subId_$subscriptionId")
            }
            ?: handles.getOrNull(subscription.simSlotIndex)
        NativeLogger.sendLog("debug", TAG, "Selected PhoneAccountHandle: $account")
        return account
    }

    /**
     * placeCall needs no activity, which Android restricts apps from starting
     * while in the background. Starting the call activity remains the fallback.
     */
    private fun dial(
        context: Context,
        code: String,
        subscription: SubscriptionInfo,
        account: PhoneAccountHandle,
    ) {
        val uri = Uri.parse("tel:" + code.replace("#", Uri.encode("#")))
        // Best-effort: provide all widely respected extras.
        val extras = Bundle().apply {
            putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, account)
            putInt("android.telephony.extra.SUBSCRIPTION_INDEX", subscription.subscriptionId)
            putInt("subscription", subscription.subscriptionId)
            putInt("com.android.phone.extra.slot", subscription.simSlotIndex)
            putInt("slot", subscription.simSlotIndex)
            putInt("simSlot", subscription.simSlotIndex)
            putInt("simSlotIndex", subscription.simSlotIndex)
        }
        NativeLogger.sendLog("debug", TAG, "Dialing USSD code: $code with subscriptionId: ${subscription.subscriptionId}")
        try {
            val telecom = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            telecom.placeCall(uri, extras)
        } catch (error: Exception) {
            NativeLogger.sendLog("warn", TAG, "placeCall failed, starting the call activity: $error")
            context.startActivity(
                Intent(Intent.ACTION_CALL, uri)
                    .putExtras(extras)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
    }

    private fun waitForResponse(result: MethodChannel.Result, check: Int, lastStepIndex: Int) {
        if (UssdSession.finalResponse.isNotEmpty()) {
            finish { result.success(response()) }
            return
        }
        if (check >= MAX_WAIT_CHECKS) {
            // Timeout: return whatever we have (possibly empty)
            finish { result.success(response().apply { put("timeout", true) }) }
            return
        }

        // A recording walks every step of the code, so it only times out when
        // a step stops progressing, not on the length of the code.
        val progressed = UssdSession.isGettingSignature && UssdSession.currentStepIndex != lastStepIndex
        mainHandler.postDelayed({
            waitForResponse(result, if (progressed) 1 else check + 1, UssdSession.currentStepIndex)
        }, WAIT_CHECK_MILLIS)
    }

    private fun response(): MutableMap<String, Any?> = mutableMapOf(
        "lastresponse" to UssdSession.finalResponse,
        "conversation" to UssdSession.conversation.toList(),
        "signatureComplete" to UssdSession.signatureComplete,
        "offerChanged" to UssdSession.offerChanged,
    )

    private fun fail(result: MethodChannel.Result, code: String, message: String) {
        finish { result.error(code, message, null) }
    }

    /** The engine that asked may be gone by now; the queue must still move on. */
    private fun finish(reply: () -> Unit) {
        try {
            reply()
        } catch (error: Exception) {
            NativeLogger.sendLog("warn", TAG, "Could not deliver the USSD result: $error")
        }
        reset()
        queue.pollFirst()?.invoke()
    }

    private fun reset() {
        screenOn?.release()
        screenOn = null
        UssdSession.finalResponse = ""
        UssdSession.ussdSteps.clear()
        UssdSession.currentStepIndex = 0
        UssdSession.isRunning = false
        UssdSession.conversation.clear()
        UssdSession.procedure = listOf()
        UssdSession.isGettingSignature = false
        UssdSession.signatureComplete = false
        UssdSession.offerChanged = false
        UssdSession.pagesTakenOnStep = 0
    }
}
