package ee.forgr.plugin.screenrecorder

import org.junit.Assert.assertEquals
import org.junit.Test

class RecordingWindowMetricsTest {
    @Test
    fun applyToWithWindowBounds_doesNotSwapLandscapeDimensions() {
        val base = dev.bmcreations.scrcast.config.Options()
        val options = base.copy(video = base.video.copy(width = -1, height = -1))
        val (width, height) = 1920 to 1080
        val resolved = VideoSizeResolver.applyTo(options, width, height)
        assertEquals(1920, resolved.video.width)
        assertEquals(1080, resolved.video.height)
    }
}