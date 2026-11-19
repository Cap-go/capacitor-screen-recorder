package ee.forgr.plugin.screenrecorder

import android.os.Build
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RecordingServiceStartPolicyTest {
    @Test
    fun shouldUseStartForegroundService_fromOreo() {
        assertTrue(RecordingServiceStartPolicy.shouldUseStartForegroundService(Build.VERSION_CODES.O))
        assertTrue(RecordingServiceStartPolicy.shouldUseStartForegroundService(Build.VERSION_CODES.O + 1))
    }

    @Test
    fun shouldUseStartForegroundService_falseBeforeOreo() {
        assertFalse(RecordingServiceStartPolicy.shouldUseStartForegroundService(Build.VERSION_CODES.N))
    }
}