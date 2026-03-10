package com.bsat.app

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

import com.bsat.app.UssdSession
import com.bsat.app.UssdResponseHandler
import com.bsat.app.Utils.MiscUtils

import android.os.Bundle
import android.widget.EditText
import android.widget.TextView
import android.widget.Toast
import android.content.Context
import android.content.pm.PackageManager

import com.bsat.app.NativeLogger

class USSDResponderService : AccessibilityService() {

    val allowedClasses = listOf(
        "androidx.appcompat.app.AlertDialog", // Generic Android
        "android.app.AlertDialog", // Samsung devices / Generic Android
        "com.originui.widget.dialog.n", // VIVO devices
        "androidx.appcompat.app.e", // OPPO devices
        "com.android.internal.widget.AlertDialog", // Samsung devices
        "com.android.systemui.dialogs.AlertDialog", // Xiaomi devices
        "com.transsion.widgetslib.dialog.PromptDialog", // Tecno devices
        "miuix.appcompat.app.AlertDialog", // XIAOMI & Redmi devices
        "miuix.appcompat.app.n", // XIAOMI & Redmi devices
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

        NativeLogger.sendLog("debug", "USSDResponderService", "Received event: package=$packageName, class=$className, eventType=${event?.eventType}, device=${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}")

        if (event?.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED 
            && className in allowedClasses 
            && packageName in allowedPackages
        ) {
            if(UssdSession.ussdSteps.isEmpty()) {
                return
            }

            val root = rootInActiveWindow ?: return

            val rootPackageName = root.packageName?.toString()
            if (rootPackageName !in allowedPackages) {
                return
            }

            logNodeTree(root)

            val sendBtn = findButtonByText(root, "Send") ?: findButtonByText(root, "OK")?: findButtonByText(root, "Done") ?: findButtonByText(root, "Got it")

            if (sendBtn == null) {
                    return
            }

            val responseText = extractAllTextNodes(root)

            if (UssdSession.currentStepIndex < UssdSession.ussdSteps.size) {
                var nextInput = UssdSession.ussdSteps[UssdSession.currentStepIndex++]

                    var optionText: String? = MiscUtils().extractOptionText(responseText, nextInput)

                    if(UssdSession.acceptedProcedure.isNotEmpty()) {
                        val expectedOption = UssdSession.acceptedProcedure[UssdSession.currentStepIndex-2]["option"] as? String
                        // check if the expected option text contains the extracted option text. This is to handle cases where the USSD response might have additional text around the option number.
                        if(expectedOption != null && optionText != null) {
                            if(!expectedOption.contains(optionText, ignoreCase = true)) {
                                if(UssdSession.autoSwitch) {

                                    var nextBestOption = MiscUtils().findOptionIndex(responseText, expectedOption)
                                
                                    if(nextBestOption == null) {
                                        val cancelBtn = findButtonByText(root, "Cancel") ?: findButtonByText(root, "Close")
                                        UssdSession.finalResponse = "Offer might have changed. Cannot find expected option $expectedOption"
                                        UssdResponseHandler.sendSuccess(UssdSession.finalResponse) // Notify the MethodChannel
                                        cancelBtn?.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                                        return
                                    }
                                    else {
                                        nextInput = nextBestOption
                                    }
                                } else {
                                    val cancelBtn = findButtonByText(root, "Cancel") ?: findButtonByText(root, "Close")
                                    UssdSession.finalResponse = "Offer might have changed. Transaction might not go through."
                                    UssdResponseHandler.sendSuccess(UssdSession.finalResponse) // Notify the MethodChannel
                                    cancelBtn?.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                                    return
                                }
                            } else {
                                NativeLogger.sendLog("debug", "UssdSession", "Auto-switching to stopped. Expected option: $expectedOption, Extracted option: $optionText, Next input: $nextInput")
                            }
                        }
                    }
                UssdSession.wholeConversation[responseText] = nextInput
            
                val inputNode = findNodeByClass(root, EditText::class.java.name)

                if(UssdSession.isGettingSignature && UssdSession.currentStepIndex == UssdSession.ussdSteps.size) {
                    // If we're in the process of getting a signature, we want to capture the response text of each step without sending any input. So we set the nextInput to an empty string to avoid sending anything.
                    nextInput = ""
                    // press "cancel" or "close" button if it exists to end the session after capturing the final response
                    val cancelBtn = findButtonByText(root, "Cancel") ?: findButtonByText(root, "Close")
                    UssdSession.finalResponse = "sd"
                    UssdResponseHandler.sendSuccess(responseText) // Notify the MethodChannel
                    cancelBtn?.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                }
                else {
                    inputNode?.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, Bundle().apply {
                        putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, nextInput)
                    })

                    sendBtn?.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                }
                // end session if inputnode is null.
                if (inputNode == null) {
                    UssdSession.finalResponse = responseText
                    NativeLogger.sendLog("debug", "UssdSession", "Input node is null, returning early.")
                    UssdResponseHandler.sendSuccess(responseText)
                    return
                }
            } else {
                NativeLogger.sendLog("debug", "UssdSession", "Final response: $responseText")
                NativeLogger.sendLog("debug", "UssdSession", "Whole conversation: ${UssdSession.wholeConversation}")
                UssdSession.finalResponse = responseText
                UssdResponseHandler.sendSuccess(responseText) // Notify the MethodChannel

                sendBtn?.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            }
        }
    }

    override fun onInterrupt() {}

    private fun findNodeByClass(root: AccessibilityNodeInfo?, className: String): AccessibilityNodeInfo? {
        if (root == null) return null
        if (root.className == className &&
            allowedPackages.contains(root.packageName?.toString())
        ) {
            return root
        }
        for (i in 0 until root.childCount) {
            val result = findNodeByClass(root.getChild(i), className)
            if (result != null) return result
        }
        return null
    }

    private fun findButtonByText(root: AccessibilityNodeInfo?, text: String): AccessibilityNodeInfo? {
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
                if (it.isNotBlank() && node.className != "android.widget.Button" && node.parent?.className != "android.widget.Button" ) texts.add(it)
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
        NativeLogger.sendLog("debug", "NodeTree", "${node.packageName}$indent${node.className}: ${node.text}")
        for (i in 0 until node.childCount) {
            logNodeTree(node.getChild(i), depth + 1)
        }
    }
}
