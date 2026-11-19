package ee.forgr.plugin.screenrecorder

import android.os.Build

object RecordingServiceStartPolicy {
    fun shouldUseStartForegroundService(sdkInt: Int = Build.VERSION.SDK_INT): Boolean {
        return sdkInt >= Build.VERSION_CODES.O
    }
}