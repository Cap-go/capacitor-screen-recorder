package ee.forgr.plugin.screenrecorder;

import android.net.Uri;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import dev.bmcreations.scrcast.config.Options;
import java.io.File;

@CapacitorPlugin(name = "ScreenRecorder")
public class ScreenRecorderPlugin extends Plugin {

    private final String pluginVersion = "8.3.18";

    private CapgoScrCast videoRecorder;
    private CapgoScrCast audioRecorder;
    private CapgoScrCast pendingRecorder = null;
    private CapgoScrCast activeRecorder = null;

    @Override
    public void load() {
        videoRecorder = CapgoScrCast.use(this.bridge.getActivity(), false);
        audioRecorder = CapgoScrCast.use(this.bridge.getActivity(), true);
        final Options options = new Options();
        videoRecorder.updateOptions(options);
        audioRecorder.updateOptions(options);

        final CapgoScrCast.ExternalStopListener externalStopListener = new CapgoScrCast.ExternalStopListener() {
            @Override
            public void onExternalStop(final String path, final String error) {
                if (activeRecorder == null) {
                    return;
                }
                activeRecorder = null;
                final JSObject ret = new JSObject();
                ret.put("url", path != null ? Uri.fromFile(new File(path)).toString() : "");
                if (error != null) {
                    ret.put("error", error);
                }
                notifyListeners("onStopped", ret);
            }
        };
        videoRecorder.setExternalStopListener(externalStopListener);
        audioRecorder.setExternalStopListener(externalStopListener);
    }

    @PluginMethod
    public void start(final PluginCall call) {
        boolean keptAlive = false;
        CapgoScrCast startRecorder = null;
        try {
            final boolean recordAudio = call.getBoolean("recordAudio", false);
            final String format = call.getString("format");
            startRecorder = recordAudio ? audioRecorder : videoRecorder;
            final CapgoScrCast recorder = startRecorder;
            final Options configuredOptions = VideoFormatResolver.INSTANCE.applyTo(recorder.getOptions(), format);
            recorder.updateOptions(configuredOptions);
            recorder.updateVideoFormat(format);

            call.setKeepAlive(true);
            keptAlive = true;
            final boolean started = recorder.record(
                new CapgoScrCast.StartListener() {
                    @Override
                    public void onStarted() {
                        if (pendingRecorder == recorder) {
                            pendingRecorder = null;
                        }
                        activeRecorder = recorder;
                        call.resolve();
                        call.release(bridge);
                    }

                    @Override
                    public void onFailed(final Throwable error) {
                        if (pendingRecorder == recorder) {
                            pendingRecorder = null;
                        }
                        if (activeRecorder == recorder) {
                            activeRecorder = null;
                        }
                        final Exception exception = error instanceof Exception ? (Exception) error : new Exception(error);
                        call.reject("Could not start screen recording", exception);
                        call.release(bridge);
                    }
                }
            );
            if (!started) {
                call.reject("Could not start screen recording", new IllegalStateException("A screen recording is already in progress"));
                call.release(bridge);
            } else {
                pendingRecorder = recorder;
            }
        } catch (final Exception e) {
            if (startRecorder != null && pendingRecorder == startRecorder) {
                pendingRecorder = null;
            }
            call.reject("Could not start screen recording", e);
            if (keptAlive) {
                call.release(bridge);
            }
        }
    }

    @PluginMethod
    public void stop(PluginCall call) {
        try {
            final CapgoScrCast recorder = activeRecorder != null ? activeRecorder : pendingRecorder;
            if (recorder != null) {
                recorder.stopRecording();
            }
            pendingRecorder = null;
            activeRecorder = null;
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
