package ee.forgr.plugin.screenrecorder

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CapgoRecordingCoordinatorTest {
    @Test
    fun tryAcquire_blocksConcurrentStartsUntilRelease() {
        CapgoRecordingCoordinator.release()
        assertTrue(CapgoRecordingCoordinator.tryAcquire())
        assertFalse(CapgoRecordingCoordinator.tryAcquire())
        CapgoRecordingCoordinator.release()
        assertTrue(CapgoRecordingCoordinator.tryAcquire())
        CapgoRecordingCoordinator.release()
    }
}
