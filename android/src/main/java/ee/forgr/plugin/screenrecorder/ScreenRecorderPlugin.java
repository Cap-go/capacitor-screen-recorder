package ee.forgr.plugin.screenrecorder;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

@CapacitorPlugin(name = "ScreenRecorder")
public class ScreenRecorderPlugin extends Plugin {

    private ScreenRecorder implementation = new ScreenRecorder();

    @PluginMethod
    public void start(PluginCall call) {
        implementation.start();
        call.resolve();
    }
    
    @PluginMethod
    public void stop(PluginCall call) {
        implementation.stop();
        call.resolve();
    }
}
