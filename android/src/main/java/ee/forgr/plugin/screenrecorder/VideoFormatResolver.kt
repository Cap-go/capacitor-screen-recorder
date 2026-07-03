package ee.forgr.plugin.screenrecorder

import android.media.MediaRecorder
import dev.bmcreations.scrcast.config.Options

object VideoFormatResolver {
    data class Resolved(
        val extension: String,
        val outputFormat: Int,
    )

    fun resolve(format: String?): Resolved {
        return when (normalize(format)) {
            "mov", "video/quicktime", "quicktime" -> Resolved(
                extension = "mp4",
                outputFormat = MediaRecorder.OutputFormat.MPEG_4,
            )
            else -> Resolved(
                extension = "mp4",
                outputFormat = MediaRecorder.OutputFormat.MPEG_4,
            )
        }
    }

    fun applyTo(options: Options, format: String?): Options {
        val resolved = resolve(format)
        return options.copy(storage = options.storage.copy(outputFormat = resolved.outputFormat))
    }

    private fun normalize(format: String?): String? {
        return format?.trim()?.lowercase()
    }
}
