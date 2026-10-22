package com.bsat.app

import android.os.Build

/** API 31 introduced callStateForSubscription before the calling feature flag (API 33). */
internal object CallStateFeaturePolicy {
    fun shouldBlockForMissingCallingFeature(apiLevel: Int, hasCallingFeature: Boolean): Boolean =
        apiLevel >= Build.VERSION_CODES.TIRAMISU && !hasCallingFeature
}
