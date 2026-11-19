package ee.forgr.plugin.screenrecorder

import java.io.File
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
        val path = "/data/local/tmp/record.mp4"
        val url = RecordingStopUrl.fromAbsolutePath(path)
        assertEquals(File(path).toURI().toString(), url)
    }
}