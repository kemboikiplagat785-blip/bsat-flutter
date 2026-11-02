package com.bsat.app

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

import com.bsat.app.UssdSession
import com.bsat.app.UssdResponseHandler

import android.os.Bundle
import android.widget.EditText
import android.content.Context

import com.bsat.app.NativeLogger

class USSDResponderService : AccessibilityService() {

    val allowedClasses = listOf(
        "androidx.appcompat.app.AlertDialog",
        "android.app.AlertDialog",
        "com.originui.widget.dialog.n",
        "androidx.appcompat.app.e",
        "com.android.internal.widget.AlertDialog",
        "com.android.systemui.dialogs.AlertDialog",
        "com.transsion.widgetslib.dialog.PromptDialog",
        "miuix.appcompat.app.AlertDialog",
        "miuix.appcompat.app.n",
        "com.android.phone.MMIDialogActivity",
        "androidx.appcompat.app.n",
        "androidx.appcompat.app.k"
    )

    val allowedPackages = listOf(
        "com.android.phone",
        "com.android.internal.telephony",
        "com.android.dialer",
        "com.android.mms",
        "com.android.messaging",
        "com.google.android.apps.messaging",
        "com.google.android.dialer",
        "com.google.android.apps.tachyon"
    )

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val packageName = event?.packageName?.toString()
        val className = event?.className?.toString()

        NativeLogger.sendLog(
            "debug",
            "USSDResponderService",
            "Received event: package=$packageName, class=$className, eventType=${event?.eventType}, device=${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}"
        )

        if (event?.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
            && className in allowedClasses
            && packageName in allowedPackages
        ) {
            if (UssdSession.ussdSteps.isEmpty()) {
                NativeLogger.sendLog(
                    "debug",
                    "UssdSession",
                    "No active USSD session, ignoring event."
                )
                return
            }

            val root = rootInActiveWindow ?: return

            val rootPackageName = root.packageName?.toString()
            if (rootPackageName !in allowedPackages) {
                return
            }

            logNodeTree(root)

            val sendBtn = findButtonByText(root, "Send")
                ?: findButtonByText(root, "OK")
                ?: findButtonByText(root, "Done")
                ?: findButtonByText(root, "Got it")

            if (sendBtn == null) return

            val responseText = extractAllTextNodes(root)

            if (responseText.contains("connection problem", ignoreCase = true)  || responseText.contains("connection code", ignoreCase = true) || responseText.contains("technical difficulties", ignoreCase = true) || responseText.contains("application23", ignoreCase = true) ||responseText.contains("Error from application", ignoreCase = true) || responseText.contains("invalid mmi code", ignoreCase = true)) {
                val okBtn = findButtonByText(root, "OK")
                if (okBtn != null) {
                    // A recording cannot continue; report it instead of waiting for the timeout.
                    if (UssdSession.isGettingSignature) {
                        UssdSession.finalResponse = responseText
                    }
                    okBtn.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                    NativeLogger.sendLog(
                        "debug",
                        "USSDResponderService",
                        "Connection code problem dialog detected. Pressing OK button."
                    )
                    return
                }
            }

            if (UssdSession.currentStepIndex < UssdSession.ussdSteps.size) {
                var nextInput = UssdSession.ussdSteps[UssdSession.currentStepIndex++]

                // ---------------------------------------------------------
                // 1. DYNAMIC INPUT INTERCEPTOR (Runs BEFORE Menu Logic)
                // ---------------------------------------------------------
                val isPhoneNumberPrompt = responseText.contains("number", ignoreCase = true)
                val isLikelyMenu = Regex("\\b[1-9][\\.\\-\\) :]+[A-Za-z]").findAll(responseText).count() >= 2

                if (isPhoneNumberPrompt && !isLikelyMenu) {
                    val isCurrentInputPhone = nextInput.matches(Regex("^[0-9]{9,12}$"))

                    if (!isCurrentInputPhone) {
                        val upcomingPhoneNumber = UssdSession.ussdSteps.find { it.matches(Regex("^[0-9]{9,12}$")) }
                        if (upcomingPhoneNumber != null) {
                            NativeLogger.sendLog(
                                "debug",
                                "UssdSession",
                                "Phone number prompt detected. Resyncing nextInput from '$nextInput' to '$upcomingPhoneNumber'"
                            )
                            nextInput = upcomingPhoneNumber


                            // if response text contains "Invalid choice. Try again."
                            if (responseText.contains("Invalid choice. Try again.")) {

                                val splitNumb = splitNumber(upcomingPhoneNumber)
                                nextInput = splitNumb
                                UssdSession.currentStepIndex = UssdSession.currentStepIndex - 1
                                NativeLogger.sendLog(
                                    "debug",
                                    "UssdSession",
                                    "Sending split number $splitNumb"
                                )
                            }

                            // Re-sync the index so we stay aligned on the next loops
                            val phoneIndex = UssdSession.ussdSteps.indexOf(upcomingPhoneNumber)
                            if (phoneIndex >= UssdSession.currentStepIndex - 1) {
                                UssdSession.currentStepIndex = phoneIndex + 1
                            }
                        }
                    }
                }

                val inputNode = findNodeByClass(root, EditText::class.java.name)

                // No input field: Safaricom ended the session with a message.
                if (inputNode == null) {
                    UssdSession.finalResponse = responseText
                    NativeLogger.sendLog("debug", "UssdSession", "Input node is null, returning early.")
                    UssdResponseHandler.sendSuccess(responseText)
                    sendBtn.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                    return
                }

                val stepIndex = UssdSession.currentStepIndex - 2

                if (UssdSession.isGettingSignature) {
                    UssdSession.recordStep(stepIndex, responseText, nextInput)

                    // The last input is what buys the bundle: record it, never send it.
                    if (UssdSession.currentStepIndex == UssdSession.ussdSteps.size) {
                        NativeLogger.sendLog("debug", "UssdSession", "Signature recorded: ${UssdSession.conversation.size} steps.")
                        UssdSession.signatureComplete = true
                        cancelSession(root, responseText)
                        return
                    }
                } else {
                    val decision = SignatureMatcher.decide(
                        screen = responseText,
                        plannedInput = nextInput,
                        procedure = UssdSession.procedure,
                        stepIndex = stepIndex,
                        autoSwitch = UssdSession.autoSwitch,
                        pagesTaken = UssdSession.pagesTakenOnStep
                    )
                    NativeLogger.sendLog("debug", "UssdSession", "Step ${stepIndex + 1}: planned $nextInput, decision $decision")

                    when (decision) {
                        is SignatureMatcher.Decision.Send -> {
                            nextInput = decision.input
                            UssdSession.currentStepIndex += decision.stepsSkipped
                            UssdSession.pagesTakenOnStep = 0
                        }
                        is SignatureMatcher.Decision.NextPage -> {
                            nextInput = decision.input
                            UssdSession.currentStepIndex -= 1
                            UssdSession.pagesTakenOnStep += 1
                        }
                        is SignatureMatcher.Decision.Stop -> {
                            UssdSession.offerChanged = true
                            cancelSession(root, decision.reason)
                            return
                        }
                    }
                    UssdSession.recordStep(stepIndex, responseText, nextInput)
                }

                NativeLogger.sendLog(
                    "debug",
                    "UssdSession",
                    "Next input: $nextInput, Response text: $responseText"
                )

                inputNode.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, Bundle().apply {
                    putCharSequence(
                        AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                        nextInput
                    )
                })

                sendBtn.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            } else {
                // A recording never sends anything past the steps of the code.
                if (UssdSession.isGettingSignature) {
                    cancelSession(root, responseText)
                    return
                }

                NativeLogger.sendLog("debug", "UssdSession", "Final response: $responseText")
                NativeLogger.sendLog("debug", "UssdSession", "Whole conversation: ${UssdSession.conversation}")
                UssdSession.finalResponse = responseText
                UssdResponseHandler.sendSuccess(responseText)

                sendBtn?.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            }
        }
    }

    override fun onInterrupt() {}

    private fun cancelSession(root: AccessibilityNodeInfo?, message: String) {
        val cancelBtn = findButtonByText(root, "Cancel") ?: findButtonByText(root, "Close")
        UssdSession.finalResponse = message
        UssdResponseHandler.sendSuccess(message)
        if (cancelBtn == null || !cancelBtn.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
            performGlobalAction(GLOBAL_ACTION_BACK)
        }
    }

    private fun findNodeByClass(
        root: AccessibilityNodeInfo?,
        className: String
    ): AccessibilityNodeInfo? {
        if (root == null) return null
        if (root.className == className && allowedPackages.contains(root.packageName?.toString())) return root

        for (i in 0 until root.childCount) {
            val result = findNodeByClass(root.getChild(i), className)
            if (result != null) return result
        }
        return null
    }

    private fun findButtonByText(
        root: AccessibilityNodeInfo?,
        text: String
    ): AccessibilityNodeInfo? {
        if (root == null) return null
        if (root.text?.toString()?.equals(text, ignoreCase = true) == true) {
            if (root.className == "android.widget.Button" || root.className == "android.widget.ImageButton") {
                return root
            }
            var parent = root.parent
            while (parent != null) {
                if (parent.className == "android.widget.Button" || parent.className == "android.widget.ImageButton") {
                    return parent
                }
                parent = parent.parent
            }
            return root
        }
        for (i in 0 until root.childCount) {
            val result = findButtonByText(root.getChild(i), text)
            if (result != null) return result
        }
        return null
    }

    fun extractAllTextNodes(root: AccessibilityNodeInfo?): String {
        if (root == null) return ""

        val texts = mutableListOf<String>()

        fun recurse(node: AccessibilityNodeInfo) {
            node.text?.toString()?.let {
                if (it.isNotBlank() && node.className != "android.widget.Button" && node.parent?.className != "android.widget.Button") texts.add(
                    it
                )
            }
            for (i in 0 until node.childCount) {
                node.getChild(i)?.let { recurse(it) }
            }
        }

        recurse(root)
        return texts.joinToString(" ")
    }

    fun logNodeTree(node: AccessibilityNodeInfo?, depth: Int = 0) {
        if (node == null) return
        val indent = " ".repeat(depth * 2)
        NativeLogger.sendLog(
            "debug",
            "NodeTree",
            "${node.packageName}$indent${node.className}: ${node.text}"
        )
        for (i in 0 until node.childCount) {
            logNodeTree(node.getChild(i), depth + 1)
        }
    }

    private fun splitNumber(number: String): String {
        // add a space after the 4th character

        return "${number.substring(0, 4)} ${number.substring(4)}"
    }
}
