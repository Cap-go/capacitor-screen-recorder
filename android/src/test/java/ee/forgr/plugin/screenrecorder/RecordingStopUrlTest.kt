package ee.forgr.plugin.screenrecorder

import org.junit.Assert.assertEquals
import org.junit.Test

class RecordingStopUrlTest {
    @Test
    fun fromAbsolutePath_returnsEmptyForNullOrBlank() {
        assertEquals("", RecordingStopUrl.fromAbsolutePath(null))
        assertEquals("", RecordingStopUrl.fromAbsolutePath(""))
        assertEquals("", RecordingStopUrl.fromAbsolutePath("   "))
    }

    @Test
    fun fromAbsolutePath_returnsFileUriForPath() {
        val url = RecordingStopUrl.fromAbsolutePath("/data/local/tmp/record.mp4")
        assertEquals("file:///data/local/tmp/record.mp4", url)
    }
}