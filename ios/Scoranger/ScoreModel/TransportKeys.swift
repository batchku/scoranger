import Foundation

/// The hardware keyboard's claim on the transport.
///
/// Spacebar starts and stops, as it does in every DAW and every score reader
/// with a hardware keyboard attached. An iPad on a stand with a Magic Keyboard
/// is the setup this app is used in, and reaching for a 32pt button to stop
/// the music is the wrong gesture there.
///
/// The rule that matters is the one about text: a space typed into the chat
/// input, or into a rename field, is a SPACE. A shortcut that swallows it
/// makes both fields unusable, which is a far worse bug than not having the
/// shortcut at all -- so the predicate is stated here and tested, rather than
/// living as a condition inside a view nobody can assert against.
enum TransportKeys {

    /// Whether a spacebar press should reach the transport.
    ///
    /// - `isEditingText`: a text field somewhere on screen has focus.
    /// - `isTransportShowing`: the transport is on screen. A shortcut for a
    ///   control the reader cannot see is a key that does something invisible.
    /// - `canPlay`: the arrangement has audio at all. A PDF has none, and
    ///   spacebar over one must do nothing rather than appear broken.
    static func spaceToggles(isEditingText: Bool,
                             isTransportShowing: Bool,
                             canPlay: Bool) -> Bool {
        guard !isEditingText else { return false }
        return isTransportShowing && canPlay
    }
}
