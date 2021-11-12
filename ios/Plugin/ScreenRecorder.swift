import Foundation
import Wyler

@objc public class ScreenRecorder: NSObject {
    @objc public func start() {
        screenRecorder.startRecording(saveToCameraRoll: true, errorHandler: { error in
            debugPrint("Error when recording \(error)")
        })
    }
    @objc public func stop() {
        screenRecorder.stoprecording(errorHandler: { error in
            debugPrint("Error when stop recording \(error)")
        })
    }
}
