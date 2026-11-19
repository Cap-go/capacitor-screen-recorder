package ee.forgr.plugin.screenrecorder

import org.junit.Assert.assertEquals
import org.junit.Test

class RecordingWindowMetricsTest {
    @Test
    fun applyToWithWindowBounds_doesNotSwapLandscapeDimensions() {
        val options = dev.bmcreations.scrcast.config.Options()
        val (width, height) = 1920 to 1080
        val resolved = VideoSizeResolver.applyTo(options, width, height)
        assertEquals(1920, resolved.video.width)
        assertEquals(1080, resolved.video.height)
    }
}