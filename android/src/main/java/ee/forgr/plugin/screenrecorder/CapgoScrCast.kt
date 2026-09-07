package ee.forgr.plugin.screenrecorder

import android.Manifest
import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.ServiceConnection
import android.media.MediaScannerConnection
import android.os.IBinder
import android.util.DisplayMetrics
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResult
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import com.karumi.dexter.Dexter
import com.karumi.dexter.MultiplePermissionsReport
import com.karumi.dexter.PermissionToken
import com.karumi.dexter.listener.PermissionRequest
import com.karumi.dexter.listener.multi.MultiplePermissionsListener
import dev.bmcreations.scrcast.config.Options
import dev.bmcreations.scrcast.internal.recorder.Action
import dev.bmcreations.scrcast.internal.recorder.EXTRA_ERROR
import dev.bmcreations.scrcast.internal.recorder.STATE_IDLE
import dev.bmcreations.scrcast.internal.recorder.STATE_RECORDING
import dev.bmcreations.scrcast.internal.recorder.notification.RecorderNotificationProvider
import ee.forgr.plugin.screenrecorder.service.CapgoRecorderService
import java.io.File

class CapgoScrCast private constructor(
    private val activity: ComponentActivity,
    private val recordAudio: Boolean,
) {
    var options: Options = Options()
        private set

    private var fileExtension: String = "mp4"
    private var recordingSession: Intent? = null
    private var serviceBinder: CapgoRecorderService? = null
    private var outputFile: File? = null
    private var startListener: StartListener? = null
    private var stopRequested = false

    /**
     * Notified when a recording ends without [stopRecording] having been
     * involved — the user stopped it from the system UI or the recorder
     * terminated itself (max duration / max size).
     */
    var externalStopListener: ExternalStopListener? = null
    private var receiverRegistered = false

    private val metrics by lazy {
        DisplayMetrics().apply { activity.windowManager.defaultDisplay.getMetrics(this) }
    }

    private val dpi by lazy { metrics.density }

    private val notificationProvider by lazy {
        RecorderNotificationProvider(activity, options.notification)
    }

    private val broadcaster by lazy { LocalBroadcastManager.getInstance(activity) }

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(className: ComponentName, service: IBinder) {
            val binder = service as CapgoRecorderService.LocalBinder
            serviceBinder = binder.service
            serviceBinder?.setNotificationProvider(notificationProvider)
        }

        override fun onServiceDisconnected(arg0: ComponentName) {
            serviceBinder = null
        }
    }

    private val recordingStateHandler = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                STATE_RECORDING -> {
                    startListener?.onStarted()
                    startListener = null
                }
                STATE_IDLE -> {
                    val startPending = startListener != null
                    val sessionActive = recordingSession != null
                    val error = intent.getSerializableExtra(EXTRA_ERROR) as? Throwable
                    if (error != null) {
                        startListener?.onFailed(error)
                    } else if (startPending) {
                        // The session ended before recording started and no
                        // failure was reported (e.g. the service was destroyed
                        // first) — settle the kept-alive start call anyway.
                        startListener?.onFailed(IllegalStateException("Recording stopped before it started"))
                    }
                    val savedPath = cleanupSession()
                    if (!startPending && sessionActive && !stopRequested) {
                        externalStopListener?.onExternalStop(savedPath, error?.message)
                    }
                    stopRequested = false
                }
            }
        }
    }

    private val permissionListener = object : MultiplePermissionsListener {
        override fun onPermissionsChecked(report: MultiplePermissionsReport?) {
            if (report?.areAllPermissionsGranted() == true) {
                startProjection.launch(Unit)
            } else {
                notifyStartFailed(SecurityException("Required permissions were not granted"))
            }
        }

        override fun onPermissionRationaleShouldBeShown(
            permissions: MutableList<PermissionRequest>?,
            token: PermissionToken?,
        ) {
            token?.continuePermissionRequest()
        }
    }

    private val startProjection = activity.registerForActivityResult(CapgoRecordScreen()) { result ->
        if (result.resultCode != Activity.RESULT_OK) {
            notifyStartFailed(IllegalStateException("Screen capture permission denied"))
            return@registerForActivityResult
        }
        val file = resolveOutputFile()
        if (file == null) {
            notifyStartFailed(IllegalStateException("Could not resolve screen recording output file"))
            return@registerForActivityResult
        }
        startService(result, file)
    }

    fun updateOptions(options: Options) {
        this.options = resolveVideoSize(options)
    }

    fun updateVideoFormat(format: String?) {
        val resolved = VideoFormatResolver.resolve(format)
        fileExtension = resolved.extension
        options = resolveVideoSize(
            options.copy(storage = options.storage.copy(outputFormat = resolved.outputFormat)),
        )
    }

    fun record(listener: StartListener): Boolean {
        if (!CapgoRecordingCoordinator.tryAcquire()) {
            return false
        }
        startListener = listener
        val permissions = buildList {
            add(Manifest.permission.WRITE_EXTERNAL_STORAGE)
            add(Manifest.permission.READ_EXTERNAL_STORAGE)
            if (recordAudio) {
                add(Manifest.permission.RECORD_AUDIO)
            }
        }
        Dexter.withContext(activity)
            .withPermissions(permissions)
            .withListener(permissionListener)
            .check()
        return true
    }

    private fun notifyStartFailed(error: Throwable) {
        startListener?.onFailed(error)
        startListener = null
        CapgoRecordingCoordinator.release()
    }

    fun stopRecording() {
        if (recordingSession == null) {
            return
        }
        stopRequested = true
        broadcaster.sendBroadcast(Intent(Action.Stop.name))
    }

    private fun resolveVideoSize(options: Options): Options {
        return VideoSizeResolver.applyTo(options, metrics.widthPixels, metrics.heightPixels)
    }

    private fun resolveOutputFile(): File? {
        val dir = options.storage.mediaStorageLocation ?: return null
        return File("${dir.path}${File.separator}${options.storage.fileNameFormatter()}.$fileExtension")
    }

    private fun startService(result: ActivityResult, file: File) {
        outputFile = file
        stopRequested = false
        val session = Intent(activity, CapgoRecorderService::class.java).apply {
            putExtra("code", result.resultCode)
            putExtra("data", result.data)
            putExtra("options", options)
            putExtra("outputFile", file.absolutePath)
            putExtra("dpi", dpi)
            putExtra("rotation", activity.windowManager.defaultDisplay.rotation)
            putExtra("recordAudio", recordAudio)
        }
        recordingSession = session

        try {
            broadcaster.registerReceiver(
                recordingStateHandler,
                IntentFilter().apply {
                    addAction(STATE_IDLE)
                    addAction(STATE_RECORDING)
                },
            )
            receiverRegistered = true
            activity.bindService(session, connection, Context.BIND_AUTO_CREATE)
            activity.startService(session)
        } catch (error: Exception) {
            Log.e("CapgoScreenRecorder", "Failed to start screen recording service", error)
            rollbackFailedStart(error)
        }
    }

    private fun rollbackFailedStart(error: Throwable) {
        unregisterRecordingReceiver()
        recordingSession = null
        outputFile = null
        stopRequested = false
        notifyStartFailed(error)
    }

    private fun unregisterRecordingReceiver() {
        if (!receiverRegistered) {
            return
        }
        try {
            broadcaster.unregisterReceiver(recordingStateHandler)
        } catch (ignored: Exception) {
            Log.d("CapgoScreenRecorder", "Receiver already unregistered", ignored)
        }
        receiverRegistered = false
    }

    private fun cleanupSession(): String? {
        startListener = null
        unregisterRecordingReceiver()

        try {
            activity.unbindService(connection)
        } catch (ignored: Exception) {
            Log.d("CapgoScreenRecorder", "Service already unbound", ignored)
        }

        recordingSession?.let { activity.stopService(it) }
        recordingSession = null

        val savedPath = outputFile?.absolutePath
        savedPath?.let { path ->
            MediaScannerConnection.scanFile(activity, arrayOf(path), null) { path, uri ->
                Log.i("CapgoScreenRecorder", "Saved recording: $path uri=$uri")
            }
        }
        outputFile = null
        CapgoRecordingCoordinator.release()
        return savedPath
    }

    interface StartListener {
        fun onStarted()
        fun onFailed(error: Throwable)
    }

    fun interface ExternalStopListener {
        fun onExternalStop(path: String?, error: String?)
    }

    companion object {
        @JvmStatic
        fun use(activity: ComponentActivity, recordAudio: Boolean): CapgoScrCast {
            return CapgoScrCast(activity, recordAudio)
        }
    }
}
