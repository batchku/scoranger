import Foundation

/// Everything a UI test can leave behind for the next one, cleared in one place.
///
/// Test fixture only: `isRequested` is false unless the test runner passed the
/// flag, so a shipped run never reaches any of it.
///
/// It is TOTAL BY CONSTRUCTION, and that is the whole point. What stood here
/// before was a list of the preferences someone had remembered -- it set
/// `layout` and cleared the drawings -- so every `@AppStorage` key added after
/// it was written leaked: `chatInputLines2`, `showTransport`,
/// `touchDiagnostics`, `didRevealTransport`. A list of keys goes stale on the
/// next feature; the app's persistent domain cannot, because it is defined as
/// "whatever this app has stored".
///
/// The one deliberate omission is the keychain. Nothing in the suite writes an
/// API key, and wiping it would throw away the OMR key the headless runs adopt
/// from `Documents/omr-key.txt` -- a real cost for no leak.
enum TestReset {

    /// The flags that ask for it. `-resetViewPreferences` was passed by
    /// `TransportVisibility` and read by nothing: it named a reset that had no
    /// switch behind it.
    static var isRequested: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-resetLibrary") || args.contains("-resetViewPreferences")
    }

    /// Every stored preference, gone.
    ///
    /// Must run BEFORE the first view exists. `@AppStorage` reads its value
    /// when the property wrapper is constructed, so a wipe performed from a
    /// view's `.task` -- which is where the old one ran -- leaves the values
    /// already read standing, and the test sees the previous test's setting
    /// for the whole of its first screen.
    static func wipeDefaults() {
        guard isRequested, let domain = Bundle.main.bundleIdentifier else { return }
        UserDefaults.standard.removePersistentDomain(forName: domain)
    }

    /// The state that lives in Documents rather than in defaults.
    ///
    /// `workspace/` is not here: `PythonEngine.start()` removes it under
    /// `-resetLibrary`, before it configures the engine on it, which is the
    /// only moment it can safely be thrown away.
    static func wipeDocuments() {
        guard isRequested else { return }
        let docs = FileManager.default.urls(for: .documentDirectory,
                                            in: .userDomainMask)[0]
        // Pencil marks are keyed by score and version and so outlive the
        // workspace `-resetLibrary` throws away: a stroke left by one test
        // turned up on a later test's canvas and read as a drawing leaking
        // between versions.
        for name in ["annotations", "inbox", "inbox-chat", "outbox-chat", ".ingesting"] {
            try? FileManager.default.removeItem(at: docs.appending(path: name))
        }
    }

    /// Both, in the order the app needs them.
    static func wipe() {
        wipeDefaults()
        wipeDocuments()
    }
}
