import XCTest

/// The guide's lessons tick themselves off when the practice box shows the
/// user did it, and lead on to the next one.
final class GuideTests: XCTestCase {

    func testLessonCompletesAndMovesOn() {
        let app = XCUIApplication()
        app.launchEnvironment["PREVIEW_LESSON"] = "1"
        app.launch()
        let field = app.textFields["Tap here to bring up the keyboard"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Skip this one"].exists, "not done before trying")
        field.tap()
        field.typeText("α")
        let next = app.buttons["Next lesson"]
        XCTAssertTrue(next.waitForExistence(timeout: 3), "α in the box finishes the lesson")
        next.tap()
        XCTAssertTrue(app.staticTexts["Let it finish for you"].waitForExistence(timeout: 3))
    }
}
