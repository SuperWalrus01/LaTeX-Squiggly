import XCTest

/// Holds keys down on Apple's keyboard and on ours, side by side in the same
/// app, so screenshots taken during each hold can be compared. Run with
/// scripts/compare-keys.sh, which takes the screenshots.
final class KeyLookTests: XCTestCase {

    func testHoldKeys() {
        for (screen, name) in [("-systemKeyboard", "apple"), ("-keyboardPreview", "ours")] {
            let app = XCUIApplication()
            app.launchArguments = [screen]
            app.launch()
            sleep(3)
            // Apple's keyboard opens with a one-time slide-to-type tip.
            let tip = app.buttons["Continue"]
            if tip.waitForExistence(timeout: 3) { tip.tap(); sleep(1) }
            for key in ["g", "q", "p", "e"] {
                print("LOOK hold \(name) \(key) \(Date().timeIntervalSince1970)")
                point(of: key, in: app, name: name).press(forDuration: 3)
                sleep(1)
            }
            app.terminate()
        }
    }

    /// Apple's keys by name. Ours by where they are on a 390-point screen,
    /// since the touch surface over them is what takes the press.
    private func point(of key: String, in app: XCUIApplication, name: String) -> XCUICoordinate {
        let element = app.keys[key].firstMatch
        if name == "apple", element.waitForExistence(timeout: 3) {
            return element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        }
        let points: [String: CGVector] = ["q": .init(dx: 23, dy: 637), "e": .init(dx: 99, dy: 637),
                                          "g": .init(dx: 195, dy: 692), "p": .init(dx: 367, dy: 637)]
        return app.coordinate(withNormalizedOffset: .zero).withOffset(points[key]!)
    }
}
