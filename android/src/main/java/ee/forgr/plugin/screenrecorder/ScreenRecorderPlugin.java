package ee.forgr.plugin.screenrecorder;

import android.media.MediaRecorder;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import dev.bmcreations.scrcast.ScrCast;
import dev.bmcreations.scrcast.config.NotificationConfig;
import dev.bmcreations.scrcast.config.Options;
import dev.bmcreations.scrcast.config.StorageConfig;
import dev.bmcreations.scrcast.config.VideoConfig;

@CapacitorPlugin(name = "ScreenRecorder")
public class ScreenRecorderPlugin extends Plugin {

    private final String pluginVersion = "8.2.23";
    private static final int DEFAULT_VIDEO_WIDTH = -1;
    private static final int DEFAULT_VIDEO_HEIGHT = -1;
    private static final int DEFAULT_VIDEO_BITRATE = 5_000_000;
    private static final int DEFAULT_VIDEO_FRAME_RATE = 30;
    private static final int DEFAULT_VIDEO_MAX_LENGTH_SECS = 0;

    private ScrCast recorder;

    @Override
    public void load() {
        recorder = ScrCast.use(this.bridge.getActivity());
        Options options = new Options();
        recorder.updateOptions(options);
    }

    @PluginMethod
    public void start(PluginCall call) {
        try {
            recorder.updateOptions(buildOptions(call));
            recorder.record();
            call.resolve();
        } catch (final Exception e) {
            call.reject("Failed to start screen recording", e);
        }
    }

    @PluginMethod
    public void stop(PluginCall call) {
        recorder.stopRecording();
        call.resolve();
    }

    @PluginMethod
    public void getPluginVersion(final PluginCall call) {
        try {
            final JSObject ret = new JSObject();
            ret.put("version", this.pluginVersion);
            call.resolve(ret);
        } catch (final Exception e) {
            call.reject("Could not get plugin version", e);
        }
    }

    private Options buildOptions(final PluginCall call) {
        final JSObject videoOptions = call.getObject("video");
        final int width = readInt(videoOptions, "width", DEFAULT_VIDEO_WIDTH, true);
        final int height = readInt(videoOptions, "height", DEFAULT_VIDEO_HEIGHT, true);
        final int bitrate = readInt(videoOptions, "bitrate", DEFAULT_VIDEO_BITRATE, false);
        final int frameRate = readInt(videoOptions, "frameRate", DEFAULT_VIDEO_FRAME_RATE, false);
        final int maxLengthSecs = readInt(videoOptions, "maxLengthSecs", DEFAULT_VIDEO_MAX_LENGTH_SECS, false);

        final VideoConfig videoConfig = new VideoConfig(width, height, MediaRecorder.VideoEncoder.H264, bitrate, frameRate, maxLengthSecs);
        return new Options(videoConfig, new StorageConfig(), new NotificationConfig(), false, 0, false);
    }

    private int readInt(final JSObject source, final String key, final int fallback, final boolean allowNegativeOne) {
        if (source == null || !source.has(key)) {
            return fallback;
        }
        final Integer value = source.getInteger(key);
        if (value == null) {
            return fallback;
        }
        if (allowNegativeOne && value == -1) {
            return value;
        }
        return Math.max(value, 0);
    }
}
