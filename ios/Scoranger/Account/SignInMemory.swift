import Foundation

/// Whether THIS DEVICE has ever signed in. One bit, local, and the only thing
/// that decides whether launch brings Firebase up.
///
/// Principle 1 (design/FIREBASE.md §0.2): a signed-out install makes no
/// Firebase contact of any kind, and `check_signed_out.py` holds the app to
/// it. That rule is what made every launch look signed out: Firebase keeps the
/// session in the keychain, but the app never configured Firebase at launch,
/// so it never asked, so `SignIn.state` began at `.signedOut` every time and
/// Ali signed in again every time he opened the app.
///
/// The two are reconciled by this bit. A device that has never signed in has
/// it clear and launch touches nothing -- the principle holds exactly as
/// before. A device that HAS signed in has it set, and launch restores the
/// session Firebase already kept. Signing out clears it, so a person who left
/// is not quietly brought back.
///
/// `UserDefaults`, not the keychain: this is not a secret, it is a note to
/// ourselves about whether there is anything in the keychain worth reading.
struct SignInMemory {

    private let defaults: UserDefaults
    private static let key = "signin.hasSignedInBefore"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasSignedInBefore: Bool {
        defaults.bool(forKey: Self.key)
    }

    func remember() {
        defaults.set(true, forKey: Self.key)
    }

    func forget() {
        defaults.removeObject(forKey: Self.key)
    }
}
