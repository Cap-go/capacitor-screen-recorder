package ee.forgr.plugin.screenrecorder

import java.io.File

object RecordingStopUrl {
    @JvmStatic
    fun fromAbsolutePath(absolutePath: String?): String {
        if (absolutePath.isNullOrBlank()) {
            return ""
        }
        return File(absolutePath).toURI().toString()
    }
}