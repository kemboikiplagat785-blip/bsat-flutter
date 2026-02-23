package com.bsat.app

object UssdSession {
    var interpunct: String = "·"
    var ussdSteps: MutableList<String> = mutableListOf()
    var usedUssdSteps: MutableList<String> = mutableListOf()
    var currentStepIndex = 0
    var finalResponse: String = ""
    var isRunning = false
    var ussdDialed: String = ""
    var isGettingSignature = false

    var acceptedProcedure: List<Map<String, Any>> = listOf()
    var autoSwitch: Boolean = false

    // var wholeConversation, map of step entries to their responses
    var wholeConversation: MutableMap<String, String> = mutableMapOf()
}
 