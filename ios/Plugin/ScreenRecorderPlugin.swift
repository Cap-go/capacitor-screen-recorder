import Foundation
import Capacitor
import Wyler

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitorjs.com/docs/plugins/ios
 */
@objc(ScreenRecorderPlugin)
public class ScreenRecorderPlugin: CAPPlugin {
    private let implementation = ScreenRecorder()

    @objc func start(_ call: CAPPluginCall) {
        implementation.startRecording(saveToCameraRoll: true, errorHandler: { error in
            debugPrint("Error when recording \(error)")
        })
        call.resolve()
    }
    @objc func stop(_ call: CAPPluginCall) {
        implementation.stoprecording(errorHandler: { error in
            debugPrint("Error when stop recording \(error)")
        })
        call.resolve()
    }
}
