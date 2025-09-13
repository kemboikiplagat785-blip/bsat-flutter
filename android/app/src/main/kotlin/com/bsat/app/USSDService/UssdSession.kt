package com.bsat.app

object UssdSession {
    var ussdSteps: MutableList<String> = mutableListOf()
    var currentStepIndex = 0
    var finalResponse: String = ""
    var isRunning = false
}
