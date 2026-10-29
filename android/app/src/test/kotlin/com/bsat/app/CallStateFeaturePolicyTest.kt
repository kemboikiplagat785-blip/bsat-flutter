package com.bsat.app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CallStateFeaturePolicyTest {
    @Test
    fun api31And32DoNotRequireCallingFeatureFlag() {
        assertFalse(CallStateFeaturePolicy.shouldBlockForMissingCallingFeature(31, false))
        assertFalse(CallStateFeaturePolicy.shouldBlockForMissingCallingFeature(32, false))
    }

    @Test
    fun api33AndLaterRequireCallingFeatureFlag() {
        assertTrue(CallStateFeaturePolicy.shouldBlockForMissingCallingFeature(33, false))
        assertTrue(CallStateFeaturePolicy.shouldBlockForMissingCallingFeature(35, false))
        assertFalse(CallStateFeaturePolicy.shouldBlockForMissingCallingFeature(33, true))
    }
}
