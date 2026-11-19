import Foundation
import UIKit

final class ScreenCaptureMonitor {
    var onStateChanged: ((Bool) -> Void)?
    private var observer: NSObjectProtocol?

    var isCaptured: Bool {
        UIScreen.main.isCaptured
    }

    func start() {
        guard observer == nil else {
            return
        }
        observer = NotificationCenter.default.addObserver(
            forName: UIScreen.capturedDidChangeNotification,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            guard let self else {
                return
            }
            self.onStateChanged?(UIScreen.main.isCaptured)
        }
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }
}