package ee.forgr.plugin.screenrecorder

import dev.bmcreations.scrcast.config.Options
import dev.bmcreations.scrcast.config.StorageConfig
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Test

class RecordingWindowMetricsTest {
    private fun autoSizeOptions(): Options {
        val tmpDir = File(System.getProperty("java.io.tmpdir"))
        return Options(storage = StorageConfig(directory = tmpDir))
    }

    @Test
    fun applyToWithWindowBounds_keepsLandscapeMetricsUnswapped() {
        val resolved = VideoSizeResolver.applyTo(autoSizeOptions(), 1280, 720)
        assertEquals(1280, resolved.video.width)
        assertEquals(720, resolved.video.height)
    }
}