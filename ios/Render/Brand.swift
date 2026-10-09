import SwiftUI
import UIKit

/// LaTeX Squiggly's look, as on the website and the Chrome extension: warm
/// paper, brown ink and squiggle orange, each with its dark-mode partner.
extension Color {
    static let paper = brand(light: 0xFAF7EE, dark: 0x17130F)
    static let card = brand(light: 0xFFFDF8, dark: 0x201A15)
    static let ink = brand(light: 0x221A12, dark: 0xF2ECE2)
    static let inkSoft = brand(light: 0x5C5147, dark: 0xB8ADA0)
    static let rule = brand(light: 0xE4DCCB, dark: 0x322A22)
    static let squiggle = brand(light: 0xE2660F, dark: 0xFF8A3D)

    private static func brand(light: UInt32, dark: UInt32) -> Color {
        func color(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        return Color(UIColor { $0.userInterfaceStyle == .dark ? color(dark) : color(light) })
    }
}

/// The hand-drawn "LaTeX Squiggly", in squiggle orange.
struct Wordmark: View {
    var body: some View {
        Image("Wordmark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(Color.squiggle)
            .accessibilityLabel("LaTeX Squiggly")
    }
}

extension View {
    /// Paper behind a list or form, cards for its rows, orange controls.
    func squigglyList() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.paper)
            .tint(.squiggle)
    }

}

enum SquigglyAppearance {
    /// The brand's rounded headings in navigation bars.
    static func apply() {
        let rounded = { (size: CGFloat, weight: UIFont.Weight) -> UIFont in
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            return base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
        }
        let ink = UIColor(Color.ink)
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: rounded(34, .bold), .foregroundColor: ink]
        bar.titleTextAttributes = [.font: rounded(17, .semibold), .foregroundColor: ink]
    }
}
