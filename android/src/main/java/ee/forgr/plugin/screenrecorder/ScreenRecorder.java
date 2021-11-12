package ee.forgr.plugin.screenrecorder;

import android.util.Log;

public class ScreenRecorder {
    val recorder = ScrCast.use(activity)

    public void start() {
        Log.i("start");
        recorder.record();
    }

    public void stop() {
        Log.i("stop");
        recorder.stopRecording();
    }
}
