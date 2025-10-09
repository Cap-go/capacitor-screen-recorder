import XCTest
@testable import ScreenRecorderPlugin

final class ScreenRecorderPluginTests: XCTestCase {
    func testEcho() {
        // Ensure the sample helper still returns the provided value.
        let implementation = ScreenRecorder()
        let value = "Hello, World!"
        let result = implementation.echo(value)

        XCTAssertEqual(value, result)
    }
}
