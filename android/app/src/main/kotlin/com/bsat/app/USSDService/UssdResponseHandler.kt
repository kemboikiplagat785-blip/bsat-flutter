package com.bsat.app

import io.flutter.plugin.common.MethodChannel

object UssdResponseHandler {
    var flutterResult: MethodChannel.Result? = null

    fun sendSuccess(response: String) {
        flutterResult?.success(response)
        flutterResult = null // Reset to prevent multiple calls
    }

    fun sendError(errorCode: String, errorMessage: String) {
        flutterResult?.error(errorCode, errorMessage, null)
        flutterResult = null // Reset to prevent multiple calls
    }
}
