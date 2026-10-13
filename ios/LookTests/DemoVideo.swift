import XCTest

/// Types through the keyboard's features for the demo video, tapping the
/// real keys of the in-app keyboard. Each scene prints `SCENE time caption`
/// for scripts/make-demo.sh, which records the simulator and adds captions.
/// Coordinates are for a 390 by 844 point screen.
final class DemoVideo: XCTestCase {

    private var app = XCUIApplication()
    private enum Page { case letters, numbers, symbols, math }
    private var page = Page.letters

    private static let rowY: [CGFloat] = [637, 692, 746, 800]
    private static let tenX: [CGFloat] = [23, 61, 99, 137, 176, 214, 252, 290, 328, 367]
    private static let punctuationX: [CGFloat] = [85, 140, 195, 250, 305]

    func testDemo() {
        open("-keyboardPreview")

        scene("Type LaTeX, press space, get the symbol")
        type("\\alpha + \\beta \\to \\infty ", pause: 0.5)
        sleep(1)

        scene("Suggestions finish commands for you")
        type("\\the")
        sleep(1)
        tapAt(120, 591)    // the first suggestion, θ
        sleep(1)
        type(" ")

        scene("Changed your mind? Delete brings the LaTeX back")
        type("\\pi ")
        sleep(1)
        tapAt(358, 746)    // delete
        sleep(2)
        type(" ")

        scene("Hold a key for accents and related symbols")
        type("\ncaf")
        hold(99, 637, slideTo: 171)   // e, then é
        sleep(1)
        sleep(1)

        scene("\u{2211} in the bar has Greek letters and maths symbols")
        type(" ")
        tapAt(361, 591)    // ∑ in the bar
        page = .math
        sleep(1)
        for x in [23, 61, 99, 137] as [CGFloat] { tapAt(x, 637); usleep(400_000) }
        tapAt(29, 800)     // ABC
        page = .letters
        sleep(1)

        scene("For an image, write your maths between $ signs")
        type("\n")
        tapAt(98, 591)     // $…$ in the bar
        sleep(1)
        type("x = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}")
        sleep(2)

        scene("Tap it for a big preview: size, light or dark, Copy")
        tapAt(150, 591)
        sleep(2)
        tapAt(159, 750)    // L
        sleep(1)
        tapAt(337, 750)    // dark
        sleep(1)
        tapAt(113, 797)    // Copy
        sleep(2)

        scene("Copied: paste it into any chat")
        sleep(2)
        tapAt(290, 797)    // Keys
        sleep(1)

        scene("LaTeX on: nothing converts, everything stays LaTeX")
        tapAt(200, 400)    // the empty page: the cursor goes to the end
        type("\n")
        sleep(1)
        tapAt(40, 591)     // LaTeX
        sleep(1)
        type("\\int_0^1 x^2 \\, dx = \\frac{1}{3}")
        sleep(3)
        app.terminate()

        open("-shareSheet", text: "The roots are $x = \\frac{-b \\pm \\sqrt{\\Delta}}{2a}$ when $a \\neq 0$.")
        scene("Select LaTeX in any app, tap Share, then LaTeX Squiggly")
        sleep(4)
        app.terminate()

        open("-messagesEditor", text: "\\int_0^\\infty e^{-x^2} dx = \\frac{\\sqrt{\\pi}}{2}")
        scene("In Messages, the picture goes straight into your message")
        sleep(4)
        app.terminate()
        scene("end")
    }

    // MARK: - Helpers

    private func open(_ screen: String, text: String = "") {
        app = XCUIApplication()
        app.launchArguments = [screen, "-output", "unicode"]
        app.launchEnvironment["PREVIEW_TEXT"] = text
        app.launch()
        page = .letters
        sleep(3)
    }

    private func scene(_ caption: String) {
        print("SCENE \(Date().timeIntervalSince1970) \(caption)")
    }

    private func tapAt(_ x: CGFloat, _ y: CGFloat) {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y)).tap()
    }

    private func hold(_ x: CGFloat, _ y: CGFloat, slideTo toX: CGFloat) {
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: x, dy: y))
            .press(forDuration: 1.2, thenDragTo: origin.withOffset(CGVector(dx: toX, dy: y)))
    }

    /// Types `text` key by key, changing pages as a person would.
    private func type(_ text: String, pause: Double = 0) {
        for character in text {
            press(character)
            if pause > 0, character == " " { usleep(UInt32(pause * 1_000_000)) }
        }
    }

    private func press(_ character: Character) {
        let letters = Array("qwertyuiop"), home = Array("asdfghjkl"), bottom = Array("zxcvbnm")
        let numbers = Array("1234567890"), numbers2 = Array("-/:;()$&@\"")
        let symbols = Array("[]{}#%^*+="), symbols2 = Array("_\\|~<>€£¥•")
        let punctuation = Array(".,?!'")
        switch character {
        case " ": tapAt(225, 800)
        case "\\": tapAt(127, 800)
        case "\n": tapAt(341, 800)
        case _ where letters.contains(character):
            go(.letters); tapAt(Self.tenX[letters.firstIndex(of: character)!], Self.rowY[0])
        case _ where home.contains(character):
            go(.letters); tapAt(41 + 38.4 * CGFloat(home.firstIndex(of: character)!), Self.rowY[1])
        case _ where bottom.contains(character):
            go(.letters); tapAt(80 + 38.4 * CGFloat(bottom.firstIndex(of: character)!), Self.rowY[2])
        case _ where numbers.contains(character):
            go(.numbers); tapAt(Self.tenX[numbers.firstIndex(of: character)!], Self.rowY[0])
        case _ where numbers2.contains(character):
            go(.numbers); tapAt(Self.tenX[numbers2.firstIndex(of: character)!], Self.rowY[1])
        case _ where symbols.contains(character):
            go(.symbols); tapAt(Self.tenX[symbols.firstIndex(of: character)!], Self.rowY[0])
        case _ where symbols2.contains(character):
            go(.symbols); tapAt(Self.tenX[symbols2.firstIndex(of: character)!], Self.rowY[1])
        case _ where punctuation.contains(character):
            if page == .letters { go(.numbers) }
            tapAt(Self.punctuationX[punctuation.firstIndex(of: character)!], Self.rowY[2])
            // An apostrophe goes back to the letters by itself.
            if character == "'" { page = .letters }
        default:
            XCTFail("cannot type \(character)")
        }
    }

    /// Changes page with the keys a person would use.
    private func go(_ target: Page) {
        guard target != page else { return }
        switch (page, target) {
        case (_, .letters):
            tapAt(29, 800)                       // ABC
        case (.letters, .numbers), (.math, .numbers):
            tapAt(29, 800)                       // 123
        case (.symbols, .numbers):
            tapAt(29, 746)                       // 123 on the symbols page
        case (.numbers, .symbols):
            tapAt(29, 746)                       // #+=
        case (_, .symbols):
            tapAt(29, 800); tapAt(29, 746)       // 123, then #+=
        default:
            break
        }
        page = target
    }
}
