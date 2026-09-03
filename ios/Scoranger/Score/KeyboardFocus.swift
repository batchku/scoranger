import UIKit

/// Whether a text field currently has the keyboard.
///
/// Asked by the spacebar shortcut, which must never swallow a space typed into
/// the chat input or a rename field (`TransportKeys`). UIKit is *supposed* to
/// give a first-responder text view priority over an unmodified key command,
/// and the version of that rule has moved between releases -- so this asks
/// directly rather than trusting it. The predicate that uses the answer is in
/// `TransportKeys`, where it can be tested; what is here is the one thing that
/// genuinely needs a live responder chain.
enum KeyboardFocus {

    static var isEditingText: Bool {
        guard let responder = current else { return false }
        // `UITextInput` covers UITextField, UITextView and anything SwiftUI
        // puts a cursor in; the search field, the chat input and every rename
        // field in the app are one of those.
        return responder is UITextInput
    }

    /// The first responder, found by asking the application to deliver a
    /// selector to whoever currently holds it. There is no public API for
    /// this, and walking the window's view tree misses responders that are not
    /// views.
    private static var current: UIResponder? {
        FirstResponderProbe.found = nil
        UIApplication.shared.sendAction(#selector(UIResponder.scorangerFindFirstResponder(_:)),
                                        to: nil, from: nil, for: nil)
        return FirstResponderProbe.found
    }
}

/// Storage for the probe above. A stored property cannot live on the
/// `UIResponder` extension, so it lives here.
private enum FirstResponderProbe {
    static weak var found: UIResponder?
}

private extension UIResponder {
    @objc func scorangerFindFirstResponder(_ sender: Any) {
        FirstResponderProbe.found = self
    }
}
