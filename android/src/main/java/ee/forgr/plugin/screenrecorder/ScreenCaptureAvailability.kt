package ee.forgr.plugin.screenrecorder

import android.os.Build

object ScreenCaptureAvailability {
    fun supportsRecordingCallbacks(sdkInt: Int = Build.VERSION.SDK_INT): Boolean {
        return sdkInt >= 35
    }
}