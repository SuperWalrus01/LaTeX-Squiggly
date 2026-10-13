import SwiftUI
import UIKit

/// A key's place in the current page: its row, and its position in the row.
struct KeyID: Hashable {
    let row: Int
    let index: Int
}

/// Where a key is drawn, reported by the key itself so touches can find it.
struct KeyFrame: Equatable {
    let id: KeyID
    let key: Key
    let frame: CGRect
}

struct KeyFramesKey: PreferenceKey {
    static var defaultValue: [KeyFrame] = []
    static func reduce(value: inout [KeyFrame], nextValue: () -> [KeyFrame]) {
        value += nextValue()
    }
}

/// The row of options a held key shows, laid out in the keys' coordinates.
struct AlternatesPopup: Equatable {
    /// Left to right as drawn.
    let options: [Key]
    var selected: Int
    let frame: CGRect

    var cellWidth: CGFloat { frame.width / CGFloat(options.count) }
}

/// What the fingers are doing, kept apart from `KeyboardModel` so a press
/// redraws only the keys, not the bar above them.
@MainActor
final class KeyPresses: ObservableObject {
    @Published private(set) var keys: Set<KeyID> = []
    @Published fileprivate(set) var popup: AlternatesPopup?

    fileprivate func show(_ keys: Set<KeyID>) {
        if self.keys != keys { self.keys = keys }
    }
}

extension KeyAction {
    /// Keys that type a character. These follow the finger as it slides.
    var typesText: Bool {
        switch self {
        case .insert, .math: return true
        default: return false
        }
    }
}

/// One surface over all the keys that takes every touch, the way the system
/// keyboard does, rather than a gesture per key. That is what lets a finger
/// slide from one key to another, lets a touch in a gap land on the nearest
/// key, and lets a second finger type the first finger's key straight away.
struct KeyTouchLayer: UIViewRepresentable {
    static let space = "keys"

    let model: KeyboardModel
    let frames: [KeyFrame]
    let metrics: Metrics

    func makeUIView(context: Context) -> KeyTouchView {
        KeyTouchView(model: model)
    }

    func updateUIView(_ view: KeyTouchView, context: Context) {
        view.frames = frames
        // The bar is above the keys, and a pop-up can reach up over it but
        // no further: nothing a keyboard draws shows above its own top.
        view.popupCeiling = -metrics.stripHeight + 2
    }
}

final class KeyTouchView: UIView {

    /// One finger on the keys.
    private final class Finger {
        /// The key it landed on.
        let origin: KeyFrame
        /// The key under it now.
        var current: KeyFrame
        /// The page it landed on, for 123 or ABC pressed and slid onto a key.
        let page: KeyboardPage
        let start: CGPoint
        var lastX: CGFloat
        /// Moved far enough to count as sliding, not just a finger rolling.
        var sliding = false
        /// Already typed, because another finger landed first.
        var spent = false
        /// Showing the held key's options.
        var choosing = false
        /// Space as a trackpad: where the finger was when it began, and how
        /// many characters it has moved the cursor since.
        var cursorAnchor: CGFloat?
        var cursorSteps = 0
        var repeats = 0
        var timer: Timer?
        /// The touch itself, to notice one that ended without telling us.
        weak var touch: UITouch?

        init(origin: KeyFrame, page: KeyboardPage, at point: CGPoint, touch: UITouch) {
            self.touch = touch
            self.origin = origin
            current = origin
            self.page = page
            start = point
            lastX = point.x
        }
    }

    private let model: KeyboardModel
    private var presses: KeyPresses { model.presses }
    private var fingers: [ObjectIdentifier: Finger] = [:]
    var frames: [KeyFrame] = []
    var popupCeiling: CGFloat = -44

    init(model: KeyboardModel) {
        self.model = model
        super.init(frame: .zero)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Finding the key

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// The row nearest the touch, then the key nearest it in that row, so the
    /// gaps and the ends of short rows belong to a key, as in iOS.
    private func key(at point: CGPoint) -> KeyFrame? {
        guard let row = frames.min(by: { abs($0.frame.midY - point.y) < abs($1.frame.midY - point.y) })?.id.row
        else { return nil }
        return frames.filter { $0.id.row == row }.min {
            Self.distance(from: point, to: $0.frame) < Self.distance(from: point, to: $1.frame)
        }
    }

    /// Where a finger lands between two letters, or right on the edge of one,
    /// the letter more likely to come next in English wins, the way the
    /// system keyboard quietly grows the key you probably meant. A touch on a
    /// key types that key, and English odds are no guide inside maths or a
    /// command, where `\nabla` or `xy` are meant.
    private func likelyKey(at point: CGPoint) -> KeyFrame? {
        guard let nearest = key(at: point) else { return nil }
        guard model.page == .letters, Self.letter(of: nearest) != nil,
              !nearest.frame.insetBy(dx: 3, dy: 3).contains(point),
              model.typingWords else { return nearest }
        let previous = model.previousCharacter
        // How far a touch strays, in points, and how much the odds count.
        // Very unlikely letters are floored, so no letter is ever ruled out.
        let spread: Float = 5
        let weight: Float = 0.3
        func score(_ key: KeyFrame) -> Float? {
            guard let letter = Self.letter(of: key),
                  let odds = LetterOdds.log(letter, after: previous).map({ max($0, -6) }) else { return nil }
            let d = Float(Self.distance(from: point, to: key.frame))
            guard d < 12 || key.id == nearest.id else { return nil }
            return -d * d / (2 * spread * spread) + weight * odds
        }
        return frames.compactMap { key in score(key).map { (key, $0) } }
            .max { $0.1 < $1.1 }?.0 ?? nearest
    }

    private static func letter(of key: KeyFrame) -> Character? {
        guard case .insert(let text) = key.key.action, text.count == 1,
              let character = text.first, character.isASCII, character.isLetter else { return nil }
        return character
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        #if DEBUG
        let start = CACurrentMediaTime()
        defer { touches.forEach { LatencyProbe.shared?.record("down", sensed: $0.timestamp, start: start) } }
        #endif
        dropLostFingers()
        for touch in touches {
            let point = touch.location(in: self)
            guard !model.cursorMode, let key = likelyKey(at: point) else { continue }
            // A new finger types the keys the others are holding, so fast
            // typing comes out in the order the keys were pressed.
            for other in fingers.values { typeEarly(other) }
            let finger = Finger(origin: key, page: model.page, at: point, touch: touch)
            fingers[ObjectIdentifier(touch)] = finger
            UIDevice.current.playInputClick()
            land(finger)
            forwardKeyboardSwitch(finger, event)
        }
        showPressed()
    }

    /// The emoji and globe keys hand their touches to iOS, which decides
    /// between the next keyboard and the list of keyboards.
    private func forwardKeyboardSwitch(_ finger: Finger, _ event: UIEvent?) {
        guard finger.origin.key.action == .nextKeyboard, let event else { return }
        model.handleInputModeList(from: self, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let finger = fingers[ObjectIdentifier(touch)], !finger.spent else { continue }
            let point = touch.location(in: self)
            finger.lastX = point.x
            if finger.origin.key.action == .nextKeyboard {
                forwardKeyboardSwitch(finger, event)
                continue
            }
            if finger.choosing {
                choose(at: point.x)
                continue
            }
            switch finger.origin.key.action {
            case .space:
                trackCursor(finger, x: point.x)
            case .backspace:
                break
            default:
                follow(finger, to: point)
            }
        }
        showPressed()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        #if DEBUG
        let start = CACurrentMediaTime()
        defer { touches.forEach { LatencyProbe.shared?.record("up", sensed: $0.timestamp, start: start) } }
        #endif
        for touch in touches {
            guard let finger = fingers.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            finger.timer?.invalidate()
            if finger.origin.key.action == .nextKeyboard {
                forwardKeyboardSwitch(finger, event)
                continue
            }
            lift(finger)
        }
        showPressed()
    }

    /// iOS cancels a touch when one of its own gestures, or SwiftUI's,
    /// claims it, which can happen to an ordinary tap in the middle of the
    /// keys. A finger that stayed where it landed was a tap, so it still
    /// types its key, as on the system keyboard. One that moved was a swipe.
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let finger = fingers.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            finger.timer?.invalidate()
            let point = touch.location(in: self)
            let stayed = hypot(point.x - finger.start.x, point.y - finger.start.y) < 12
            if finger.cursorAnchor != nil {
                model.setCursorMode(false)
            } else if finger.choosing {
                presses.popup = nil
            } else if stayed, !finger.sliding, finger.origin.key.action != .nextKeyboard {
                lift(finger)
            }
        }
        showPressed()
    }

    /// Fingers whose touch ended without our hearing of it, as when the view
    /// was rebuilt mid-press. Left behind, a space held as a trackpad would
    /// keep every other key from typing.
    private func dropLostFingers() {
        for (id, finger) in fingers where finger.touch.map({ $0.phase == .ended || $0.phase == .cancelled }) ?? true {
            finger.timer?.invalidate()
            fingers[id] = nil
        }
        if model.cursorMode, !fingers.values.contains(where: { $0.cursorAnchor != nil }) {
            model.setCursorMode(false)
        }
    }

    /// A finger rolls a few points as it presses and lifts, and that must not
    /// change the key. Only a deliberate slide, well into another key, does.
    /// A letter slides only onto other characters: a thumb rolling off `b`
    /// onto space still types `b`, rather than nothing.
    private func follow(_ finger: Finger, to point: CGPoint) {
        if !finger.sliding {
            guard hypot(point.x - finger.start.x, point.y - finger.start.y) > 12 else { return }
            finger.sliding = true
            finger.timer?.invalidate()
        }
        guard let key = key(at: point), key.id != finger.current.id,
              key.frame.insetBy(dx: 2, dy: 2).contains(point),
              key.key.action.typesText || !finger.origin.key.action.typesText else { return }
        finger.current = key
    }

    // MARK: - What each key does

    /// Shift and the page keys act as the finger lands, so it can slide on to
    /// the key it wants. Delete starts deleting. Space and keys with options
    /// wait to see if they are held. Everything else waits for the lift.
    private func land(_ finger: Finger) {
        let action = finger.origin.key.action
        switch action {
        case .shift, .page:
            model.perform(action)
        case .backspace:
            model.perform(.backspace)
            repeatBackspace(finger, after: 0.45)
        case .space:
            // Held, space becomes a trackpad, as in iOS. Not before: a slow
            // press is still a space.
            finger.timer = after(0.5) { [weak self] in self?.startCursorMode(finger) }
        case .insert, .math:
            guard !Alternates.options(for: finger.origin.key).isEmpty else { break }
            finger.timer = after(0.45) { [weak self] in self?.showAlternates(finger) }
        default:
            break
        }
    }

    private func lift(_ finger: Finger) {
        guard !finger.spent else { return }
        if finger.cursorAnchor != nil {
            // The finger was moving the cursor, not asking for a space.
            model.setCursorMode(false)
            return
        }
        if finger.choosing {
            typeChoice()
            return
        }
        let origin = finger.origin.key.action
        let key = finger.current
        switch origin {
        case .backspace:
            break
        case .space:
            model.perform(.space)
        case .insert, .math, .shift:
            if key.key.action.typesText { model.perform(key.key.action) }
        case .page:
            // Pressed and slid on to a key: type it and go back, as in iOS.
            if key.key.action.typesText {
                model.perform(key.key.action)
                model.page = finger.page
            }
        default:
            // Return and the like only count if the finger is still on them.
            if key == finger.origin { model.perform(origin) }
        }
    }

    private func typeEarly(_ finger: Finger) {
        guard !finger.spent, finger.cursorAnchor == nil else { return }
        let origin = finger.origin.key.action
        if finger.choosing {
            typeChoice()
        } else if origin.typesText, finger.current.key.action.typesText {
            model.perform(finger.current.key.action)
        } else if origin == .space {
            model.perform(.space)
        } else {
            return
        }
        finger.spent = true
        finger.timer?.invalidate()
    }

    // MARK: - Held keys

    /// Opens the held key's options above it, growing away from the nearer
    /// edge of the keyboard, with the key's own character over the finger.
    private func showAlternates(_ finger: Finger) {
        guard !finger.spent, !finger.sliding, fingers.values.contains(where: { $0 === finger }) else { return }
        var options = Alternates.options(for: finger.origin.key)
        guard !options.isEmpty else { return }
        let key = finger.origin.frame
        let cell = max(key.width + 4, 34)
        let width = cell * CGFloat(options.count)
        let leftward = key.midX > bounds.midX
        if leftward { options.reverse() }
        var x = leftward ? key.maxX + 2 - width : key.minX - 2
        x = min(max(x, 2), bounds.width - 2 - width)
        let frame = CGRect(x: x, y: max(key.minY - 58, popupCeiling), width: width, height: 54)
        finger.choosing = true
        presses.popup = AlternatesPopup(options: options, selected: leftward ? options.count - 1 : 0,
                                        frame: frame)
        choose(at: finger.lastX)
        showPressed()
    }

    /// The option over the finger, or the nearest end past either side.
    private func choose(at x: CGFloat) {
        guard var popup = presses.popup else { return }
        let index = Int(((x - popup.frame.minX) / popup.cellWidth).rounded(.down))
        popup.selected = min(max(index, 0), popup.options.count - 1)
        if presses.popup != popup { presses.popup = popup }
    }

    private func typeChoice() {
        guard let popup = presses.popup else { return }
        presses.popup = nil
        model.perform(popup.options[popup.selected].action)
    }

    // MARK: - Delete and space

    /// Delete repeats while held, and after a couple of seconds goes a word
    /// at a time, as in iOS.
    private func repeatBackspace(_ finger: Finger, after delay: TimeInterval) {
        finger.timer = after(delay) { [weak self] in
            guard let self, self.fingers.values.contains(where: { $0 === finger }) else { return }
            finger.repeats += 1
            let words = finger.repeats > 20
            if words { self.model.deleteWordBackward() } else { self.model.perform(.backspace) }
            self.repeatBackspace(finger, after: words ? 0.25 : 0.09)
        }
    }

    /// Once space is held, sliding moves the cursor a character per few
    /// points. Before that, a thumb sliding as it taps space still types a
    /// space, as in iOS.
    private func trackCursor(_ finger: Finger, x: CGFloat) {
        guard let anchor = finger.cursorAnchor else { return }
        let steps = Int((x - anchor) / 8)
        if steps != finger.cursorSteps {
            model.moveCursor(by: steps - finger.cursorSteps)
            finger.cursorSteps = steps
        }
    }

    private func startCursorMode(_ finger: Finger) {
        guard !finger.spent, finger.cursorAnchor == nil,
              fingers.values.contains(where: { $0 === finger }) else { return }
        finger.timer?.invalidate()
        finger.cursorAnchor = finger.lastX
        finger.cursorSteps = 0
        model.setCursorMode(true)
        showPressed()
    }

    // MARK: - Helpers

    private func showPressed() {
        let held = fingers.values.filter { !$0.spent && !$0.choosing && $0.cursorAnchor == nil }
        presses.show(Set(held.map(\.current.id)))
    }

    /// A one-off timer on the main run loop, which is where touches arrive.
    private func after(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Timer {
        Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
    }
}
