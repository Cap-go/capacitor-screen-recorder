import Foundation
import Capacitor

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitorjs.com/docs/plugins/ios
 */
@objc(ScreenRecorderPlugin)
public class ScreenRecorderPlugin: CAPPlugin, CAPBridgedPlugin {
    private let PLUGIN_VERSION: String = "7.2.5"
    public let identifier = "ScreenRecorderPlugin"
    public let jsName = "ScreenRecorder"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "start", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stop", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getPluginVersion", returnType: CAPPluginReturnPromise)
    ]
    private let implementation = ScreenRecorder()

    @objc func start(_ call: CAPPluginCall) {
        implementation.startRecording(saveToCameraRoll: true, handler: { error in
            if let error = error {
                debugPrint("Error when start recording \(error)")
                call.reject("Cannot start recording")
            } else {
                call.resolve()
            }
        })
    }
    @objc func stop(_ call: CAPPluginCall) {
        implementation.stoprecording(handler: { error in
            if let error = error {
                debugPrint("Error when stop recording \(error)")
                call.reject("Cannot stop recording")
            } else {
                call.resolve()
            }
        })
    }

    @objc func getPluginVersion(_ call: CAPPluginCall) {
        call.resolve(["version": self.PLUGIN_VERSION])
    }

}
