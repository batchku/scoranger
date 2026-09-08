import SwiftUI

/// The account, in Settings, and nowhere else.
///
/// design/FIREBASE.md §0.2. It sits here rather than behind a tab or a launch
/// prompt because signing in is OPTIONAL: no screen in this app requires an
/// account, and a reader who never signs in should never be asked. This
/// section is what they would find if they went looking.
struct AccountSection: View {
    @EnvironmentObject var signIn: SignIn
    /// Only to let go of its listeners on the way out. Signed in or out, this
    /// section shows nothing about shared set lists.
    @EnvironmentObject var shared: SharedSetlists

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BandHeader("Account")
            VStack(alignment: .leading, spacing: Theme.Metric.s12) {
                switch signIn.state {
                case .signedOut, .failed:
                    signedOut
                case .working:
                    Text("Signing in…").typeRole(.data).foregroundStyle(Theme.Ink.ink2)
                case .signedIn(let account):
                    signedIn(account)
                }
                if case .failed(let reason) = signIn.state {
                    Text(reason).typeRole(.data).foregroundStyle(Theme.Ink.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("account-error")
                }
            }
            .padding(.horizontal, Theme.Metric.s16)
            .padding(.vertical, Theme.Metric.s12)
        }
    }

    // MARK: - signed out

    @ViewBuilder
    private var signedOut: some View {
        // Said first, and plainly. The reader is not being sold an account:
        // everything they already do keeps working without one.
        Text("Your library works without an account. Sign in only to share "
             + "setlists with other people.")
            .typeRole(.data).foregroundStyle(Theme.Ink.ink2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("account-explains-optional")

        if signIn.isAvailable {
            // ONE component for both, so they cannot drift apart again.
            ProviderButton(provider: .google) {
                guard let presenter = Self.topViewController() else { return }
                Task { await signIn.signInWithGoogle(presenting: presenter) }
            }

            ProviderButton(provider: .apple, enabled: signIn.appleIsAvailable) {
                Task { await signIn.signInWithApple() }
            }

            if !signIn.appleIsAvailable {
                // SAID, not silently dead. Ali tapped this and nothing
                // happened at all, which is the worst outcome: a control that
                // looks live, does nothing, and explains nothing.
                Text("Sign in with Apple needs a capability this build does "
                     + "not carry yet. Use Google for now — it signs you into "
                     + "the same account either way.")
                    .typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("account-apple-unavailable")
            }
        } else {
            Text("This build has no Firebase configuration, so signing in is "
                 + "unavailable. Everything else works.")
                .typeRole(.data).foregroundStyle(Theme.Ink.ink3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("account-unavailable")
        }
    }

    // MARK: - signed in

    @ViewBuilder
    private func signedIn(_ account: SignIn.Account) -> some View {
        ScreenRow(title: account.displayName ?? "Signed in",
                  value: account.email ?? "private address",
                  leads: false,
                  identifier: "account-identity") {}
            .disabled(true)

        if account.email == nil {
            // §12.10. Worth saying here rather than at the moment an invitation
            // silently fails to find them.
            Text("You signed in with a private address, so people cannot invite "
                 + "you by email. Ask them for an invite code instead.")
                .typeRole(.data).foregroundStyle(Theme.Ink.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("account-private-address")
        }

        PanelButton(title: "Sign out", identifier: "sign-out") {
            // Both, and in this order: the shared set lists have to let go of
            // their listeners before the account they were opened for is gone,
            // or they keep publishing the previous person's music.
            shared.signedOut()
            signIn.signOut()
            // Any markup being pushed was going to a set list this iPad can no
            // longer read.
            DrawingStore.shared.onSave = nil
        }

        // The promise, in the place a person would worry about it.
        Text("Signing out keeps your library on this iPad. Nothing is deleted.")
            .typeRole(.data).foregroundStyle(Theme.Ink.ink3)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("account-signout-keeps")
    }

    /// Google's flow needs a view controller to present from, and SwiftUI has
    /// none to give. This is the one place that reaches for UIKit.
    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}