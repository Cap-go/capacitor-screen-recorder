package ee.forgr.plugin.screenrecorder

import dev.bmcreations.scrcast.config.Options

object VideoSizeResolver {
    const val MAX_WIDTH = 1920
    const val MAX_HEIGHT = 1080

    fun applyTo(options: Options, displayWidth: Int, displayHeight: Int): Options {
        val resolvedWidth = if (options.video.width == -1) displayWidth else options.video.width
        val resolvedHeight = if (options.video.height == -1) displayHeight else options.video.height
        val (width, height) = clamp(resolvedWidth, resolvedHeight)
        return options.copy(video = options.video.copy(width = width, height = height))
    }

    fun clamp(width: Int, height: Int): Pair<Int, Int> {
        var w = makeEven(width.coerceAtLeast(2))
        var h = makeEven(height.coerceAtLeast(2))

        if (w <= MAX_WIDTH && h <= MAX_HEIGHT) {
            return w to h
        }

        val scale = minOf(MAX_WIDTH.toFloat() / w, MAX_HEIGHT.toFloat() / h)
        w = makeEven((w * scale).toInt().coerceAtLeast(2))
        h = makeEven((h * scale).toInt().coerceAtLeast(2))
        return w to h
    }

    fun makeEven(value: Int): Int = if (value % 2 == 0) value else value - 1
}
