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
import dev.bmcreations.scrcast.recorder.RecordingState
import ee.forgr.plugin.screenrecorder.service.CapgoRecorderService
import java.io.File

class CapgoScrCastWithAudio private constructor(private val activity: ComponentActivity) {
    var options: Options = Options()
        private set

    private var recordingSession: Intent? = null
    private var serviceBinder: CapgoRecorderService? = null
    private var outputFile: File? = null

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
            if (intent?.action == STATE_IDLE) {
                cleanupSession()
            }
        }
    }

    private val permissionListener = object : MultiplePermissionsListener {
        override fun onPermissionsChecked(report: MultiplePermissionsReport?) {
            startProjection.launch(Unit)
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
            return@registerForActivityResult
        }
        val file = resolveOutputFile() ?: return@registerForActivityResult
        startService(result, file)
    }

    fun updateOptions(options: Options) {
        this.options = handleDynamicVideoSize(options)
    }

    fun record() {
        Dexter.withContext(activity)
            .withPermissions(
                Manifest.permission.WRITE_EXTERNAL_STORAGE,
                Manifest.permission.READ_EXTERNAL_STORAGE,
                Manifest.permission.RECORD_AUDIO,
            )
            .withListener(permissionListener)
            .check()
    }

    fun stopRecording() {
        broadcaster.sendBroadcast(Intent(Action.Stop.name))
    }

    private fun resolveOutputFile(): File? {
        val dir = options.storage.mediaStorageLocation ?: return null
        return File("${dir.path}${File.separator}${options.storage.fileNameFormatter()}.mp4")
    }

    private fun startService(result: ActivityResult, file: File) {
        outputFile = file
        val session = Intent(activity, CapgoRecorderService::class.java).apply {
            putExtra("code", result.resultCode)
            putExtra("data", result.data)
            putExtra("options", options)
            putExtra("outputFile", file.absolutePath)
            putExtra("dpi", dpi)
            putExtra("rotation", activity.windowManager.defaultDisplay.rotation)
        }
        recordingSession = session

        broadcaster.registerReceiver(
            recordingStateHandler,
            IntentFilter().apply {
                addAction(STATE_IDLE)
                addAction(STATE_RECORDING)
            },
        )

        activity.bindService(session, connection, Context.BIND_AUTO_CREATE)
        activity.startService(session)
    }

    private fun cleanupSession() {
        try {
            broadcaster.unregisterReceiver(recordingStateHandler)
        } catch (_: Exception) {
        }

        try {
            activity.unbindService(connection)
        } catch (_: Exception) {
        }

        recordingSession?.let { activity.stopService(it) }
        recordingSession = null

        outputFile?.let { file ->
            MediaScannerConnection.scanFile(activity, arrayOf(file.absolutePath), null) { path, uri ->
                Log.i("CapgoScreenRecorder", "Saved recording: $path uri=$uri")
            }
        }
        outputFile = null
    }

    private fun handleDynamicVideoSize(options: Options): Options {
        var reconfig = options
        if (options.video.width == -1) {
            reconfig = reconfig.copy(video = reconfig.video.copy(width = metrics.widthPixels))
        }
        if (options.video.height == -1) {
            reconfig = reconfig.copy(video = reconfig.video.copy(height = metrics.heightPixels))
        }
        return reconfig
    }

    companion object {
        @JvmStatic
        fun use(activity: ComponentActivity): CapgoScrCastWithAudio {
            return CapgoScrCastWithAudio(activity)
        }
    }
}
