import UIKit

/// The class iOS loads for the keyboard, named in Info.plist as
/// NSExtensionPrincipalClass. It only installs the keyboard view and tells
/// the model when the host app's text changes.
final class KeyboardViewController: UIInputViewController, KeyboardHost {

    private lazy var model = KeyboardModel(host: self)

    override func loadView() {
        let keyboard = KeyboardInputView(model: model)
        inputView = keyboard
        addChild(keyboard.hosting)
        keyboard.hosting.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.refresh(autoShift: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // iOS holds touches near the screen's edges back for its own swipes,
        // which makes Q, A, P and the bottom row lag. The system keyboard
        // is not held back, so this one is not either.
        view.window?.gestureRecognizers?.forEach { $0.delaysTouchesBegan = false }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        model.textChanged()
    }

    /// Cursor moves too, so the bar follows the cursor into and out of braces.
    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        model.textChanged()
    }
}
