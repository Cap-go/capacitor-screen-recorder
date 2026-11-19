package ee.forgr.plugin.screenrecorder

import android.os.Build
import android.util.DisplayMetrics
import androidx.activity.ComponentActivity

object RecordingWindowMetrics {
    fun currentSize(activity: ComponentActivity): Pair<Int, Int> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = activity.windowManager.currentWindowMetrics.bounds
            return bounds.width() to bounds.height()
        }
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        activity.windowManager.defaultDisplay.getRealMetrics(metrics)
        return metrics.widthPixels to metrics.heightPixels
    }
}