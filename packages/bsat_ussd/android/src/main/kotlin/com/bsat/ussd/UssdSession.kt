package com.bsat.ussd

object UssdSession {
    var interpunct: String = "·"
    var ussdSteps: MutableList<String> = mutableListOf()
    var usedUssdSteps: MutableList<String> = mutableListOf()
    var currentStepIndex = 0
    var finalResponse: String = ""
    var isRunning = false
    var ussdDialed: String = ""
    var isGettingSignature = false

    // The whole code goes in the dial itself; Safaricom's reply ends the session.
    var isOneCall = false

    // True only once a signature recording reached the last step of the code.
    var signatureComplete = false

    // True when the signature stopped this session before the last step.
    var offerChanged = false

    var procedure: List<SignatureMatcher.RecordedStep> = listOf()
    var autoSwitch: Boolean = false
    var pagesTakenOnStep = 0

    // Screens in step order. A list, because two steps can show the same text.
    val conversation: MutableList<Map<String, String>> = mutableListOf()

    /** Keeps conversation[stepIndex] aligned with the code's steps. */
    fun recordStep(stepIndex: Int, screen: String, input: String) {
        while (conversation.size > stepIndex) conversation.removeAt(conversation.size - 1)
        while (conversation.size < stepIndex) {
            conversation.add(mapOf("options" to "", "choice" to ussdSteps[conversation.size + 1]))
        }
        conversation.add(mapOf("options" to screen, "choice" to input))
    }
}
