package ee.forgr.plugin.screenrecorder

import android.content.Context
import android.os.Build
import android.view.WindowManager
import androidx.annotation.RequiresApi

class ScreenCaptureDetector(context: Context) {
    private val appContext = context.applicationContext
    private var isCaptured = false
    private var callbackRegistered = false

    @RequiresApi(35)
    private var screenRecordingCallback: WindowManager.ScreenRecordingCallback? = null

    fun isScreenCaptured(): Boolean {
        return isCaptured
    }

    fun start(onCapturedChanged: (Boolean) -> Unit) {
        if (!ScreenCaptureAvailability.supportsRecordingCallbacks()) {
            return
        }
        if (callbackRegistered) {
            return
        }
        registerCallback(onCapturedChanged)
    }

    fun stop() {
        if (!ScreenCaptureAvailability.supportsRecordingCallbacks()) {
            return
        }
        if (Build.VERSION.SDK_INT >= 35) {
            unregisterCallback()
        }
    }

    @RequiresApi(35)
    private fun registerCallback(onCapturedChanged: (Boolean) -> Unit) {
        val windowManager = appContext.getSystemService(WindowManager::class.java)
        val callback = WindowManager.ScreenRecordingCallback { state ->
            val captured = state == WindowManager.SCREEN_RECORDING_STATE_RECORDING
            isCaptured = captured
            onCapturedChanged(captured)
        }
        screenRecordingCallback = callback
        windowManager.addScreenRecordingCallback(appContext.mainExecutor, callback)
        callbackRegistered = true
    }

    @RequiresApi(35)
    private fun unregisterCallback() {
        val callback = screenRecordingCallback ?: return
        val windowManager = appContext.getSystemService(WindowManager::class.java)
        windowManager.removeScreenRecordingCallback(callback)
        screenRecordingCallback = null
        callbackRegistered = false
        isCaptured = false
    }
}