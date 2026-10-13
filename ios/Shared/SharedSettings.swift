import Foundation

/// Settings the app sets and the keyboard follows, kept in the App Group
/// they share. The keyboard can only read them with Full Access, so each
/// setting has to make sense left off.
enum SharedSettings {
    static let group = "group.com.keenanjusak.latex-squiggly.ios"

    private static let defaults = UserDefaults(suiteName: group)

    /// A capital at the start of each sentence, as the system keyboard does.
    /// Off by default, since x and X differ in maths.
    static var autoCapitals: Bool {
        get { defaults?.bool(forKey: "autoCapitals") ?? false }
        set { defaults?.set(newValue, forKey: "autoCapitals") }
    }
}
