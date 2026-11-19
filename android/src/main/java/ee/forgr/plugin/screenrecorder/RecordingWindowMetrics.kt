package ee.forgr.plugin.screenrecorder

import android.os.Build
import android.util.DisplayMetrics
import androidx.activity.ComponentActivity

object RecordingWindowMetrics {
    fun currentSize(activity: ComponentActivity): Pair<Int, Int> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Maximum bounds match full-display capture better than the task window (e.g. split-screen).
            val bounds = activity.windowManager.maximumWindowMetrics.bounds
            return bounds.width() to bounds.height()
        }
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        activity.windowManager.defaultDisplay.getRealMetrics(metrics)
        return metrics.widthPixels to metrics.heightPixels
    }
}