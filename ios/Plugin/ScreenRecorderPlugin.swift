import Foundation
import Capacitor

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitorjs.com/docs/plugins/ios
 */
@objc(ScreenRecorderPlugin)
public class ScreenRecorderPlugin: CAPPlugin {
    private let implementation = ScreenRecorder()

    @objc func start(_ call: CAPPluginCall) {
        implementation.start()
        call.resolve()
    }
    @objc func stop(_ call: CAPPluginCall) {
        implementation.stop()
        call.resolve()
    }
}
