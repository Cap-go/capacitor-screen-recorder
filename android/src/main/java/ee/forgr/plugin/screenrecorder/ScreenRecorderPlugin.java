package ee.forgr.plugin.screenrecorder;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import dev.bmcreations.scrcast.ScrCast;
import dev.bmcreations.scrcast.config.Options;

@CapacitorPlugin(name = "ScreenRecorder")
public class ScreenRecorderPlugin extends Plugin {

    private final String pluginVersion = "8.2.24";
    private ScrCast recorder;
    private Options options;

    @Override
    public void load() {
        recorder = ScrCast.use(this.bridge.getActivity());
        options = new Options();
        recorder.updateOptions(options);
    }

    @PluginMethod
    public void start(PluginCall call) {
        try {
            final boolean recordAudio = call.getBoolean("recordAudio", false);

            options = new Options();
            options.setAudioEnabled(recordAudio);

            recorder.updateOptions(options);
            recorder.record();

            call.resolve();
        } catch (Exception e) {
            call.reject("Could not start screen recording", e);
        }
    }

    @PluginMethod
    public void stop(PluginCall call) {
        try {
            recorder.stopRecording();
            call.resolve();
        } catch (Exception e) {
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
