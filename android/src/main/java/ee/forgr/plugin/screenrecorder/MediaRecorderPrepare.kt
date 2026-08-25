package ee.forgr.plugin.screenrecorder

import android.media.MediaRecorder

internal object MediaRecorderPrepare {
    fun tryPrepare(recorder: MediaRecorder?): Throwable? {
        return try {
            recorder?.prepare()
            null
        } catch (error: Throwable) {
            error
        }
    }
}
