import SwiftUI
import UIKit

/// What the keyboard needs from whoever shows it. `UIInputViewController`
/// already has all of it; the app's debug preview supplies its own.
@MainActor
protocol KeyboardHost: AnyObject {
    var textDocumentProxy: UITextDocumentProxy { get }
    var needsInputModeSwitchKey: Bool { get }
    var hasFullAccess: Bool { get }
    func advanceToNextInputMode()
    /// The user's text replacements and contact names, for spelling.
    func requestSupplementaryLexicon(completion: @escaping (UILexicon) -> Void)
}

/// The keyboard's root view: the system's keyboard backdrop with the SwiftUI
/// keys on top. Adopting `UIInputViewAudioFeedback` is what lets key presses
/// play the system click, when the user has keyboard clicks on.
final class KeyboardInputView: UIInputView, UIInputViewAudioFeedback {

    let hosting: UIHostingController<KeyboardView>
    private var height: NSLayoutConstraint!

    var enableInputClicksWhenVisible: Bool { true }

    init(model: KeyboardModel) {
        hosting = UIHostingController(rootView: KeyboardView(model: model))
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: Metrics.portrait.height),
                   inputViewStyle: .keyboard)
        allowsSelfSizing = true

        let content = hosting.view!
        content.backgroundColor = .clear
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        // Just below required: iOS adds its own height constraint while the
        // keyboard animates in, and a tie logs a conflict.
        height = content.heightAnchor.constraint(equalToConstant: Metrics.portrait.height)
        height.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            height,
        ])
    }

    /// Shorter in landscape, where the keys follow suit.
    override func layoutSubviews() {
        let wanted = Metrics.for(verticalSizeClass: UserInterfaceSizeClass(traitCollection.verticalSizeClass)).height
        if height.constant != wanted { height.constant = wanted }
        super.layoutSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
