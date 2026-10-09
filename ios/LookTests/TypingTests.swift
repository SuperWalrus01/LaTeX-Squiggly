import XCTest

/// Types on our keyboard in the app's debug preview and checks the text,
/// for what makes typing feel right: no capitals unless shift is tapped,
/// space that is never lost, punctuation after a suggested word, words left
/// as typed, and LaTeX converting on space.
final class TypingTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-keyboardPreview", "-output", "unicode"]
        app.launchEnvironment["PREVIEW_TEXT"] = ""
        app.launch()
        XCTAssertTrue(key("q").waitForExistence(timeout: 10) || key("Q").exists)
    }

    private var text: String { app.textViews.firstMatch.value as? String ?? "" }

    /// A key by its label, upper or lower case, whichever shift shows.
    private func key(_ label: String) -> XCUIElement {
        let exact = app.descendants(matching: .any)[label].firstMatch
        if exact.exists { return exact }
        return app.descendants(matching: .any)[label.uppercased()].firstMatch
    }

    /// The touch surface over the keys takes the touch, so tap the place,
    /// not the element.
    private func tap(_ label: String) {
        key(label).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func type(_ letters: String) {
        for character in letters {
            switch character {
            case " ": tap("space")
            case ".": tap("123"); tap("."); tap("ABC")
            case "\\": tap("\\")
            default: tap(String(character))
            }
        }
    }

    func testNoCapitalUnlessShiftIsTapped() {
        type("hi there")
        tap("123"); tap("."); tap("space")
        type("how")
        XCTAssertEqual(text, "hi there. how")
    }

    func testSpaceAfterNumbersReturnsToLetters() {
        tap("123"); tap("4"); tap("space")
        XCTAssertTrue(key("q").exists, "space on the numbers page goes back to the letters")
    }

    func testSlidingThumbOnSpaceStillTypesSpace() {
        type("so")
        let space = key("space").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        space.press(forDuration: 0.05, thenDragTo: space.withOffset(CGVector(dx: 40, dy: 0)))
        type("it")
        XCTAssertEqual(text, "so it")
    }

    func testCommandConvertsOnSpace() {
        type("\\alpha ")
        XCTAssertEqual(text, "α ")
    }

    func testNothingIsCorrectedWithoutATap() {
        type("teh")
        XCTAssertTrue(app.buttons["the"].firstMatch.waitForExistence(timeout: 3), "the bar offers the spelling")
        tap("space")
        XCTAssertEqual(text, "teh ")
    }

    func testPunctuationTakesBackSuggestionSpace() {
        type("hel")
        let suggestion = app.buttons["hello"].firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 3),
                      "The bar offers: \(app.buttons.allElementsBoundByIndex.map(\.label))")
        suggestion.tap()
        XCTAssertEqual(text, "hello ")
        tap("123"); tap(",")
        XCTAssertEqual(text, "hello,")
    }
}
