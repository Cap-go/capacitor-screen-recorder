package ee.forgr.plugin.screenrecorder

import android.media.MediaRecorder
import java.io.IOException

internal object MediaRecorderPrepare {
    fun tryPrepare(recorder: MediaRecorder?): Throwable? {
        return try {
            recorder?.prepare()
            null
        } catch (error: IOException) {
            error
        } catch (error: RuntimeException) {
            error
        }
    }
}
