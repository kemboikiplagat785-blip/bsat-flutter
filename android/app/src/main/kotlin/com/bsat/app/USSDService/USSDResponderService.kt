package com.bsat.app

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

import com.bsat.app.UssdSession
import com.bsat.app.UssdResponseHandler
import com.bsat.app.Utils.MiscUtils

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

                // Extract option text based on the finalized nextInput
                var optionText: String? = MiscUtils().extractOptionText(responseText, nextInput)

                // ---------------------------------------------------------
                // 2. MENU AUTO-SWITCH LOGIC
                // ---------------------------------------------------------
                if (UssdSession.acceptedProcedure.isNotEmpty()) {
                    val procIndex = UssdSession.currentStepIndex - 2

                    if (procIndex >= 0 && procIndex < UssdSession.acceptedProcedure.size) {
                        val expectedOption = UssdSession.acceptedProcedure[procIndex]["option"] as? String

                        // Prevent auto-switch if we are natively expecting a dynamic input, not a menu
                        val isExpectedValidMenu = !expectedOption.isNullOrBlank() &&
                                !expectedOption.equals("Option not found", ignoreCase = true) &&
                                !expectedOption.equals("Accept", ignoreCase = true)

                        if (isExpectedValidMenu) {
                            NativeLogger.sendLog(
                                "debug",
                                "UssdSession",
                                "Expected option: $expectedOption, Extracted option: $optionText, Next input: $nextInput"
                            )

                            // Short circuit execution safely prevents NullPointerException on optionText
                            val needsSwitch = optionText == null || !expectedOption.contains(optionText, ignoreCase = true)

                            if (needsSwitch) {
                                if (UssdSession.autoSwitch) {
                                    var nextBestOption = MiscUtils().findOptionIndex(responseText, expectedOption)

                                    if (nextBestOption == null) {
                                        val nextPageInput = findNextPageInput(root)
                                        if (nextPageInput != null) {
                                            UssdSession.currentStepIndex = (UssdSession.currentStepIndex - 1).coerceAtLeast(0)
                                            NativeLogger.sendLog("debug", "UssdSession", "Expected option not found. Paging with input: $nextPageInput")
                                            nextInput = nextPageInput
                                        } else {
                                            val alternativeInput = findAlternativeInputFromAcceptedOptions(responseText)
                                            if (alternativeInput != null) {
                                                NativeLogger.sendLog("debug", "UssdSession", "Similarity search found alternative input: $alternativeInput")
                                                nextInput = alternativeInput
                                            } else {
                                                cancelSession(root, "Offer might have changed. Cannot find expected option $expectedOption")
                                                return
                                            }
                                        }
                                    } else {
                                        NativeLogger.sendLog("debug", "UssdSession", "Auto-switching from $nextInput to option $nextBestOption.")
                                        nextInput = nextBestOption
                                    }

                                } else {
                                    cancelSession(root, "Offer might have changed. Transaction might not go through.")
                                    return
                                }
                            }
                        } else {

                        }
                    }
                }

                UssdSession.wholeConversation[responseText] = nextInput

                NativeLogger.sendLog(
                    "debug",
                    "UssdSession",
                    "Current step index: ${UssdSession.currentStepIndex}, Next input: $nextInput, Response text: $responseText"
                )

                val inputNode = findNodeByClass(root, EditText::class.java.name)

                if (UssdSession.isGettingSignature && UssdSession.currentStepIndex == UssdSession.ussdSteps.size) {
                    nextInput = ""
                    cancelSession(root, "sd", isSuccess = true, responseText = responseText)
                } else {
                    inputNode?.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, Bundle().apply {
                        putCharSequence(
                            AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                            nextInput
                        )
                    })

                    sendBtn?.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                }

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
                UssdResponseHandler.sendSuccess(responseText)

                sendBtn?.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            }
        }
    }

    override fun onInterrupt() {}

    private fun cancelSession(root: AccessibilityNodeInfo?, message: String, isSuccess: Boolean = false, responseText: String? = null) {
        val cancelBtn = findButtonByText(root, "Cancel") ?: findButtonByText(root, "Close")
        UssdSession.finalResponse = message
        UssdResponseHandler.sendSuccess(responseText ?: message)
        cancelBtn?.performAction(AccessibilityNodeInfo.ACTION_CLICK)
    }

    private fun findAlternativeInputFromAcceptedOptions(responseText: String): String? {
        if (UssdSession.acceptedProcedure.isEmpty()) return null

        for (step in UssdSession.acceptedProcedure) {
            val expectedOption = step["option"] as? String ?: continue
            val expectedChoice = step["choice"]?.toString() ?: continue

            if (expectedOption.isBlank() || expectedOption.equals("Option not found", ignoreCase = true) || expectedOption.equals("Accept", ignoreCase = true)) continue

            var matchIndex = responseText.indexOf(expectedOption, ignoreCase = true)

            if (matchIndex == -1) {
//                val words = expectedOption.split(Regex("\\W+")).filter { it.length > 3 }
//                for (word in words) {
//                    // FIX: Use Regex word boundaries (\b) to prevent partial substring matches
//                    // (e.g., this guarantees "Sh20" does NOT match inside "Sh200")
//                    val escapedWord = Regex.escape(word)
//                    val wordMatch = Regex("\\b$escapedWord\\b", RegexOption.IGNORE_CASE).find(responseText)
                    val wordMatch = Regex("\\b$expectedOption\\b", RegexOption.IGNORE_CASE).find(responseText)

                    if (wordMatch != null) {
                        matchIndex = wordMatch.range.first
                        break
                    }
//                }
            }

            if (matchIndex != -1) {
                val textBeforeMatch = responseText.substring(0, matchIndex).trimEnd()

                val numberRegex = Regex("(?<![0-9*#])([0-9*#]{1,3})(?![0-9*#])[\\s:.)-]*$")
                val match = numberRegex.find(textBeforeMatch)

                if (match != null) {
                    val inputChar = match.groupValues[1]
                    NativeLogger.sendLog(
                        "debug",
                        "USSDResponderService",
                        "Regex extraction found choice '$inputChar' matched via similarity to expected option: '$expectedOption'"
                    )
                    return inputChar
                } else if (UssdSession.isFullyAutonomous) {
                    NativeLogger.sendLog(
                        "debug",
                        "USSDResponderService",
                        "Regex extraction failed. Autonomous fallback to original mapped choice '$expectedChoice' for option '$expectedOption'"
                    )
                    return expectedChoice
                }
            }
        }
        return null
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

    private fun findNextPageInput(root: AccessibilityNodeInfo?): String? {
        if (root == null) return null

        val responseText = extractAllTextNodes(root)

        val regex = Regex(
            "([0-9#*nN]{1,3})[\\s:.-]*(?:page\\s*)?(?:next(?:\\s*page)?|go[t]?\\s*to\\s*next|more)",
            RegexOption.IGNORE_CASE
        )

        val matches = regex.findAll(responseText).toList()

        if (matches.isNotEmpty()) {
            val nextIdentifier = matches.lastOrNull()?.groupValues?.get(1)

            NativeLogger.sendLog(
                "debug",
                "USSDResponderService",
                "Next page identifier found: $nextIdentifier in text: $responseText"
            )

            return nextIdentifier
        }

        NativeLogger.sendLog(
            "debug",
            "USSDResponderService",
            "No next page identifier found in text: $responseText"
        )

        return null
    }

    private fun splitNumber(number: String): String {
        // add a space after the 4th character

        return "${number.substring(0, 4)} ${number.substring(4)}"
    }
}