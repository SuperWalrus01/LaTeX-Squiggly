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

    func testScriptKeyConvertsAfterSpaceStepsOut() {
        type("x")
        let square = app.buttons["x²"].firstMatch
        XCTAssertTrue(square.waitForExistence(timeout: 3),
                      "The bar offers: \(app.buttons.allElementsBoundByIndex.map(\.label))")
        square.tap()
        tap("123"); tap("2")
        tap("space")
        XCTAssertEqual(text, "x^{2}", "space steps out of the braces")
        tap("space")
        XCTAssertEqual(text, "x² ")
    }

    /// Holding LaTeX opens the keyboard's settings, and turning words off
    /// there takes them out of the bar.
    func testHoldingLaTeXOpensSettings() {
        let latex = app.buttons["LaTeX"].firstMatch
        latex.press(forDuration: 0.8)
        XCTAssertEqual(latex.value as? String, "off", "holding does not also switch LaTeX")
        let words = app.buttons["Words"].firstMatch
        XCTAssertTrue(words.waitForExistence(timeout: 2), "the settings row is open")
        XCTAssertEqual(words.value as? String, "on")
        XCTAssertEqual(app.buttons["Haptics"].firstMatch.value as? String, "off")
        words.tap()
        type("teh")
        XCTAssertFalse(app.buttons["the"].firstMatch.waitForExistence(timeout: 2), "no words in the bar")
        latex.press(forDuration: 0.8)
        app.buttons["Words"].firstMatch.tap()
        tap("delete")
        XCTAssertTrue(app.buttons["te"].firstMatch.waitForExistence(timeout: 3) || app.buttons["the"].exists,
                      "words are back")
    }

    func testDoubleSpaceStopCanBeTurnedOff() {
        app.buttons["LaTeX"].firstMatch.press(forDuration: 0.8)
        app.buttons["Space space ."].firstMatch.tap()
        type("so  ")
        XCTAssertEqual(text, "so  ")
        app.buttons["LaTeX"].firstMatch.press(forDuration: 0.8)
        app.buttons["Space space ."].firstMatch.tap()
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

    func testWordsInTextKeepTheirSpaces() {
        type("\\tex")
        let suggestion = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "\\text")).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 3),
                      "The bar offers: \(app.buttons.allElementsBoundByIndex.map(\.label))")
        suggestion.tap()
        type("two words")
        XCTAssertEqual(text, "\\text{two words}")
    }

    func testSumInTheBarOpensTheMathPageAndBack() {
        app.buttons["Greek letters and symbols"].firstMatch.tap()
        XCTAssertTrue(key("\\alpha").waitForExistence(timeout: 2), "the math page is open")
        app.buttons["letters"].firstMatch.tap()
        XCTAssertTrue(key("q").waitForExistence(timeout: 2), "back to the letters")
    }

    func testBackslashIsLeftOfSpace() {
        XCTAssertLessThan(key("\\").frame.maxX, key("space").frame.minX)
    }

    func testAutomaticCapitalsWhenTurnedOn() {
        app.terminate()
        app.launchArguments += ["-autoCapitals", "YES"]
        app.launch()
        XCTAssertTrue(key("q").waitForExistence(timeout: 10))
        type("hi")
        tap("123"); tap("."); tap("space")
        type("there")
        XCTAssertEqual(text, "Hi. There")
    }

    func testEmojiPageTypesAndRemembers() {
        tap("emoji")
        let grin = app.descendants(matching: .any)["😀"].firstMatch
        XCTAssertTrue(grin.waitForExistence(timeout: 3), "the emoji page is open")
        grin.tap()
        XCTAssertEqual(text, "😀")
        tap("letters")
        XCTAssertTrue(key("q").waitForExistence(timeout: 2), "ABC goes back to the letters")
        tap("emoji")
        XCTAssertTrue(app.staticTexts["FREQUENTLY USED"].waitForExistence(timeout: 2), "remembered next time")
    }
}
