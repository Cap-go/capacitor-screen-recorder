package ee.forgr.plugin.screenrecorder;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import dev.bmcreations.scrcast.config.Options;

@CapacitorPlugin(name = "ScreenRecorder")
public class ScreenRecorderPlugin extends Plugin {

    private final String pluginVersion = "8.3.4";

    private CapgoScrCast videoRecorder;
    private CapgoScrCast audioRecorder;
    private boolean recordingWithAudio = false;

    @Override
    public void load() {
        videoRecorder = CapgoScrCast.use(this.bridge.getActivity(), false);
        audioRecorder = CapgoScrCast.use(this.bridge.getActivity(), true);
        final Options options = new Options();
        videoRecorder.updateOptions(options);
        audioRecorder.updateOptions(options);
    }

    @PluginMethod
    public void start(final PluginCall call) {
        final boolean recordAudio = call.getBoolean("recordAudio", false);
        final String format = call.getString("format");
        recordingWithAudio = recordAudio;

        final CapgoScrCast recorder = recordAudio ? audioRecorder : videoRecorder;
        final Options configuredOptions = VideoFormatResolver.INSTANCE.applyTo(recorder.getOptions(), format);
        recorder.updateOptions(configuredOptions);
        recorder.updateVideoFormat(format);

        call.setKeepAlive(true);
        recorder.record(
            new CapgoScrCast.StartListener() {
                @Override
                public void onStarted() {
                    call.resolve();
                    call.release(bridge);
                }

                @Override
                public void onFailed(final Throwable error) {
                    recordingWithAudio = false;
                    final Exception exception = error instanceof Exception ? (Exception) error : new Exception(error);
                    call.reject("Could not start screen recording", exception);
                    call.release(bridge);
                }
            }
        );
    }

    @PluginMethod
    public void stop(PluginCall call) {
        try {
            if (recordingWithAudio) {
                audioRecorder.stopRecording();
            } else {
                videoRecorder.stopRecording();
            }
            recordingWithAudio = false;
            call.resolve();
        } catch (final Exception e) {
            call.reject("Could not stop screen recording", e);
        }
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
}
