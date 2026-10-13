import XCTest

/// Types a sentence on our keyboard with `-measureLatency`, so the app
/// writes `latency.txt` for scripts to read. Run it on a device for real
/// numbers; the simulator runs on the Mac's faster processor.
final class LatencyTests: XCTestCase {

    func testTypeASentence() {
        let app = XCUIApplication()
        app.launchArguments = ["-keyboardPreview", "-output", "unicode", "-measureLatency"]
        app.launchEnvironment["PREVIEW_TEXT"] = ""
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["q"].firstMatch.waitForExistence(timeout: 10))
        for character in "the quick brown fox jumps over the lazy dog \\alpha \\to \\infty " {
            let label = character == " " ? "space" : String(character)
            app.descendants(matching: .any)[label].firstMatch
                .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        sleep(2)
    }
}
