import Foundation

@objc public class ScreenRecorder: NSObject {
    @objc public func echo(_ value: String) -> String {
        print(value)
        return value
    }
}
