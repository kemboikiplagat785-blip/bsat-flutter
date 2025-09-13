package com.bsat.app

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

import com.bsat.app.UssdSession
import com.bsat.app.UssdResponseHandler

import android.os.Bundle
import android.widget.EditText
import android.widget.TextView
import android.widget.Toast
import android.content.Context
import android.content.pm.PackageManager

import android.util.Log

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

        Log.d("UssdSession", "Event: $event")
        
// if((event?.text?.joinToString(" ") ?: "").length > 80) {
//         // TODO: Delete the following section. 
//         // For debugging ONLY
//         // end session
//         Log.d("UssdSession", "Ending session due to long response text.")
//         UssdSession.ussdSteps.clear()
//         UssdSession.currentStepIndex = 0
//         UssdSession.isRunning = false
//         UssdSession.finalResponse = "$event"
//         UssdResponseHandler.sendSuccess(event?.text?.joinToString(" ") ?: "") // Notify the MethodChannel
// }
        // Log.d("NodetreeUssdSession", "Package: $packageName")

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
                // Log.d("UssdSession", "Root package name $rootPackageName is not in allowedPackages.")
                // Log.d("UssdSession", "Unexpected package name: $rootPackageName")
                return
            }

            logNodeTree(root)

            val sendBtn = findButtonByText(root, "Send") ?: findButtonByText(root, "OK")?: findButtonByText(root, "Done") ?: findButtonByText(root, "Got it")

            if (sendBtn == null) {
                    return
            } else {
                Log.d("UssdSession", "Found send button: ${sendBtn.text}")
            }

            val responseText = extractAllTextNodes(root)

            if (UssdSession.currentStepIndex < UssdSession.ussdSteps.size) {
                val nextInput = UssdSession.ussdSteps[UssdSession.currentStepIndex++]

                Log.d("UssdSession", "Response text: $responseText")
                Log.d("UssdSession", "Next input: $nextInput")
                Log.d("UssdSession", "currentStepIndex: ${UssdSession.currentStepIndex}, UssdStepsSize: ${UssdSession.ussdSteps.size}")

                val inputNode = findNodeByClass(root, EditText::class.java.name)
                // val inputNode = findEditTextInDialog(root)
                // Log.d("UssdSession", "Input node: $inputNode\nParent: ${inputNode?.parent}")

                inputNode?.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, Bundle().apply {
                    putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, nextInput)
                })

                sendBtn?.performAction(AccessibilityNodeInfo.ACTION_CLICK)

                // end session if inputnode is null.
                if (inputNode == null) {
                    Log.d("UssdSession", "Input node is null, ending session.")
                    UssdSession.finalResponse = responseText
                    UssdResponseHandler.sendSuccess(responseText)
                    return
                }

                Log.d("UssdSession", "Input sent: $nextInput")
            } else {
                Log.d("UssdSession", "Final response: $responseText")
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
        Log.d("NodeTree", "${node.packageName}$indent${node.className}: ${node.text}")
        for (i in 0 until node.childCount) {
            logNodeTree(node.getChild(i), depth + 1)
        }
    }
}
