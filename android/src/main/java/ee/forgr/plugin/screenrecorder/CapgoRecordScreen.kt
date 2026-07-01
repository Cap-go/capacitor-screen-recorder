package ee.forgr.plugin.screenrecorder

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import androidx.activity.result.ActivityResult
import androidx.activity.result.contract.ActivityResultContract

class CapgoRecordScreen : ActivityResultContract<Unit, ActivityResult>() {
    override fun createIntent(context: Context, input: Unit): Intent {
        val pm = context.getSystemService(MediaProjectionManager::class.java)
        return pm.createScreenCaptureIntent()
    }

    override fun parseResult(resultCode: Int, intent: Intent?): ActivityResult {
        return ActivityResult(resultCode, intent)
    }
}
