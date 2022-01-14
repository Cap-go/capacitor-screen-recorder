package ee.forgr.plugin.screenrecorder;

import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import dev.bmcreations.scrcast.ScrCast;

@CapacitorPlugin(name = "ScreenRecorder")
public class ScreenRecorderPlugin extends Plugin {

    ScrCast recorder = ScrCast.use(this.bridge.getActivity());

    @PluginMethod
    public void start(PluginCall call) {
        recorder.record();
        call.resolve();
    }
    
    @PluginMethod
    public void stop(PluginCall call) {
        recorder.stopRecording();
        call.resolve();
    }
}
