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
    fun applyTo_resolvesAutoDimensionsFromPortraitWindowBounds() {
        val resolved = VideoSizeResolver.applyTo(autoSizeOptions(), 720, 1280)
        // Clamped to 1080p cap while keeping portrait aspect.
        assertEquals(606, resolved.video.width)
        assertEquals(1080, resolved.video.height)
    }

    @Test
    fun applyTo_preservesExplicitVideoSizeRegardlessOfWindowBounds() {
        val base = autoSizeOptions()
        val options = base.copy(video = base.video.copy(width = 640, height = 480))
        val resolved = VideoSizeResolver.applyTo(options, 1920, 1080)
        assertEquals(640, resolved.video.width)
        assertEquals(480, resolved.video.height)
    }
}