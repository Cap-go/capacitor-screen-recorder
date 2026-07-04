package ee.forgr.plugin.screenrecorder

import android.media.MediaRecorder
import dev.bmcreations.scrcast.config.Options

object VideoFormatResolver {
    data class Resolved(
        val extension: String = "mp4",
        val outputFormat: Int = MediaRecorder.OutputFormat.MPEG_4,
    )

    fun resolve(@Suppress("UNUSED_PARAMETER") format: String?): Resolved {
        // Android MediaRecorder only supports MPEG-4 output.
        return Resolved()
    }

    fun applyTo(options: Options, format: String?): Options {
        val resolved = resolve(format)
        return options.copy(storage = options.storage.copy(outputFormat = resolved.outputFormat))
    }
}
