/// A short rolling record of what the user has just typed.
///
/// In memory only, bounded, and cleared aggressively. Nothing here is ever
/// written to disk or sent anywhere — see `reset()` call sites in the app
/// target for every point at which it is discarded.
public struct InputBuffer: Equatable {

    /// Long enough for any realistic command plus scripts, short enough that
    /// the buffer never accumulates a sentence.
    public static let defaultCapacity = 64

    public private(set) var text = ""
    public let capacity: Int

    public init(capacity: Int = InputBuffer.defaultCapacity) {
        self.capacity = capacity
    }

    public mutating func insert(_ string: String) {
        text += string
        if text.count > capacity {
            text.removeFirst(text.count - capacity)
        }
    }

    public mutating func deleteBackward() {
        if !text.isEmpty { text.removeLast() }
    }

    /// Called whenever we can no longer trust that the buffer reflects what is
    /// in front of the cursor: a click, an arrow key, an app switch, Return.
    public mutating func reset() {
        text = ""
    }

    public var isEmpty: Bool { text.isEmpty }
}
