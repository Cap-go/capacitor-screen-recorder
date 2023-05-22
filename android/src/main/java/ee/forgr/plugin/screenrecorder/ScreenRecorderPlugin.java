package ee.forgr.plugin.screenrecorder;

import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import dev.bmcreations.scrcast.ScrCast;
import dev.bmcreations.scrcast.config.Options;

@CapacitorPlugin(name = "ScreenRecorder")
public class ScreenRecorderPlugin extends Plugin {

  private ScrCast recorder;

  @Override
  public void load() {
    recorder = ScrCast.use(this.bridge.getActivity());
    Options options = new Options();
    recorder.updateOptions(options);
  }

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
