package ee.forgr.plugin.screenrecorder

import android.net.Uri
import java.io.File

object RecordingStopUrl {
    @JvmStatic
    fun fromAbsolutePath(absolutePath: String?): String {
        if (absolutePath.isNullOrBlank()) {
            return ""
        }
        return Uri.fromFile(File(absolutePath)).toString()
    }
}