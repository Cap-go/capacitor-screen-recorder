package ee.forgr.plugin.screenrecorder

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScreenCaptureAvailabilityTest {
    @Test
    fun supportsRecordingCallbacks_fromApi35() {
        assertTrue(ScreenCaptureAvailability.supportsRecordingCallbacks(35))
        assertTrue(ScreenCaptureAvailability.supportsRecordingCallbacks(36))
    }

    @Test
    fun supportsRecordingCallbacks_falseBeforeApi35() {
        assertFalse(ScreenCaptureAvailability.supportsRecordingCallbacks(34))
    }
}