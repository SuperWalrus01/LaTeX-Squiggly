import XCTest

/// Walks through what the user guide shows, printing `SHOT name time` once
/// each screen has settled, for scripts/make-guide.sh, which screenshots the
/// simulator throughout and keeps the frame after each mark.
final class GuideShots: XCTestCase {

    private func shot(_ name: String) {
        sleep(1)
        print("SHOT \(name) \(Date().timeIntervalSince1970)")
        sleep(2)
    }

    /// Settings: add the keyboard and allow Full Access.
    func test1Settings() {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        tap("General", in: settings)
        tap("Keyboard", in: settings)
        tap("Keyboards", in: settings)
        shot("settings-keyboards")
        tap("Add New Keyboard", in: settings)
        shot("settings-add")
        tap("LaTeX Squiggly", in: settings)
        shot("settings-added")
        tap("LaTeX Squiggly", in: settings)
        shot("settings-full-access-off")
        settings.switches.firstMatch.tap()
        shot("settings-full-access-alert")
        settings.buttons["Allow"].firstMatch.tap()
        shot("settings-full-access-on")
        settings.terminate()
    }

    /// The globe key, held, lists the keyboards to switch to.
    func test2Globe() {
        let app = XCUIApplication()
        app.launchArguments = ["-systemKeyboard"]
        app.launch()
        sleep(3)
        let tip = app.buttons["Continue"]
        if tip.waitForExistence(timeout: 3) { tip.tap(); sleep(1) }
        print("HOLD globe \(Date().timeIntervalSince1970)")
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 42, dy: 804)).press(forDuration: 4)
        app.terminate()
    }

    /// A key's balloon, a held key's options, and Copy.
    func test3Keys() {
        let app = XCUIApplication()
        app.launchArguments = ["-keyboardPreview"]
        app.launchEnvironment["PREVIEW_TEXT"] = "Hello"
        app.launch()
        sleep(3)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        print("HOLD balloon \(Date().timeIntervalSince1970)")
        origin.withOffset(CGVector(dx: 195, dy: 692)).press(forDuration: 2.5)
        sleep(1)
        print("HOLD accents \(Date().timeIntervalSince1970)")
        origin.withOffset(CGVector(dx: 99, dy: 637)).press(forDuration: 4)
        app.terminate()

        app.launchEnvironment["PREVIEW_TEXT"] = "The answer is $x = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}$"
        app.launch()
        sleep(3)
        origin.withOffset(CGVector(dx: 345, dy: 591)).tap()
        shot("copied")
        app.terminate()
    }

    /// The app's Try it tab, where the mascot waits for a first conversion.
    func test4TryTab() {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Try it"].tap()
        shot("app-try")
        app.terminate()
    }

    /// Taps the first row or button whose label starts with `label`,
    /// scrolling to it. Rows first, so a page titled the same is not it.
    private func tap(_ label: String, in app: XCUIApplication) {
        let starts = NSPredicate(format: "label BEGINSWITH %@", label)
        let candidates = [app.cells.matching(starts), app.buttons.matching(starts),
                          app.collectionViews.staticTexts.matching(starts),
                          app.tables.staticTexts.matching(starts)].map(\.firstMatch)
        var found: XCUIElement?
        for _ in 0..<20 where found == nil {
            found = candidates.first { $0.exists }
            if found == nil { usleep(400_000) }
        }
        guard let item = found else { return XCTFail("no \(label)") }
        var swipes = 0
        while !item.isHittable && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        item.tap()
        sleep(1)
    }
}
