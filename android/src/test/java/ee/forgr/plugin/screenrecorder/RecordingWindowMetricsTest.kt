package ee.forgr.plugin.screenrecorder

import org.junit.Assert.assertEquals
import org.junit.Test

class RecordingWindowMetricsTest {
    @Test
    fun applyToWithWindowBounds_keepsLandscapeMetricsUnswapped() {
        val options = dev.bmcreations.scrcast.config.Options()
        val resolved = VideoSizeResolver.applyTo(options, 1280, 720)
        assertEquals(1280, resolved.video.width)
        assertEquals(720, resolved.video.height)
    }
}