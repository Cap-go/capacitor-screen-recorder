package ee.forgr.plugin.screenrecorder

import android.content.Context
import android.os.Build
import android.view.WindowManager
import java.lang.reflect.Proxy
import java.util.concurrent.Executor

class ScreenCaptureDetector(context: Context) {
    private val appContext = context.applicationContext
    private var isCaptured = false
    private var callbackRegistered = false
    private var registeredCallback: Any? = null

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
        registerCallbackReflection(onCapturedChanged)
    }

    fun stop() {
        if (!callbackRegistered || Build.VERSION.SDK_INT < 35) {
            return
        }
        unregisterCallbackReflection()
    }

    private fun registerCallbackReflection(onCapturedChanged: (Boolean) -> Unit) {
        if (Build.VERSION.SDK_INT < 35) {
            return
        }
        runCatching {
            val windowManager = appContext.getSystemService(WindowManager::class.java)
            val callbackClass = Class.forName("android.view.WindowManager\$ScreenRecordingCallback")
            val recordingStateClass = callbackClass.declaringClass
            val recordingStateRecording = recordingStateClass
                .getField("SCREEN_RECORDING_STATE_RECORDING")
                .getInt(null)
            val handler = java.lang.reflect.InvocationHandler { _, method, args ->
                if (method.name == "onScreenRecordingStateChanged" && args != null && args.isNotEmpty()) {
                    val state = args[0] as Int
                    val captured = state == recordingStateRecording
                    isCaptured = captured
                    onCapturedChanged(captured)
                }
                null
            }
            val callback = Proxy.newProxyInstance(
                callbackClass.classLoader,
                arrayOf(callbackClass),
                handler,
            )
            val executor = appContext.mainExecutor
            val addMethod = windowManager.javaClass.getMethod(
                "addScreenRecordingCallback",
                Executor::class.java,
                callbackClass,
            )
            addMethod.invoke(windowManager, executor, callback)
            registeredCallback = callback
            callbackRegistered = true
        }.onFailure {
            callbackRegistered = false
            registeredCallback = null
        }
    }

  private fun unregisterCallbackReflection() {
        val callback = registeredCallback ?: return
        runCatching {
            val windowManager = appContext.getSystemService(WindowManager::class.java)
            val callbackClass = Class.forName("android.view.WindowManager\$ScreenRecordingCallback")
            val removeMethod = windowManager.javaClass.getMethod(
                "removeScreenRecordingCallback",
                callbackClass,
            )
            removeMethod.invoke(windowManager, callback)
        }
        registeredCallback = null
        callbackRegistered = false
        isCaptured = false
    }
}