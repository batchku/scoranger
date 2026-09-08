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
    /// A pasted invitation is put where a tapped one goes: `pendingInvite`, in
    /// front of the same "You've been invited" band, claimed by the same
    /// button. One entrance, two doors into it.
    @EnvironmentObject var state: AppState

    @State private var pasteNote: String?

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

        if let email = account.email, account.isPrivateRelay {
            // §12.10, and the copy that used to be here pointed at an "invite
            // code" this app has never had. The address itself is the answer:
            // Apple's relay is deliverable and stable for this app, and it is
            // what the token presents as a verified email -- so an invitation
            // sent to it works. It just cannot be GUESSED, so it has to be
            // handed over.
            Text("Apple gave you a private address. Invitations still work — "
                 + "send this to whoever is inviting you:")
                .typeRole(.data).foregroundStyle(Theme.Ink.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("account-relay-explains")

            Text(email)
                .typeRole(.data).foregroundStyle(Theme.Ink.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("account-relay-address")

            ShareLink(item: email) {
                Text("Send my address").typeRole(.control)
            }
            .accessibilityIdentifier("account-relay-share")
        } else if account.email == nil {
            Text("This account has no email address, so people cannot invite "
                 + "you by email yet.")
                .typeRole(.data).foregroundStyle(Theme.Ink.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("account-private-address")
        }

        pasteInvitation

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

    // MARK: - an invitation that did not arrive as a link

    /// The other iPad's way in.
    ///
    /// An invitation travels as `scoranger://invite?id=…` inside a message,
    /// and the app it is sent through decides whether that is tappable.
    /// Messages does not make a custom scheme tappable, so the reader is
    /// holding words they can only copy -- and until this button existed,
    /// copying them led nowhere. The QR code and the offline join that replace
    /// this properly are 0.7.2 (design/FIREBASE.md §11.10); this is the two
    /// lines that stop the flow dead-ending in the meantime.
    @ViewBuilder
    private var pasteInvitation: some View {
        PanelButton(title: "Paste an invitation",
                    identifier: "account-paste-invite") {
            let pasted = UIPasteboard.general.string ?? ""
            if let id = SharedInviteLink.inviteId(inPastedText: pasted) {
                state.pendingInvite = id
                pasteNote = "Invitation found. It's in your library now, "
                    + "under \"You've been invited\"."
            } else if pasted.isEmpty {
                pasteNote = "There's nothing on the clipboard to paste."
            } else {
                // Says which of the two things to copy, because "invalid" here
                // tells a person nothing they can act on.
                pasteNote = "That doesn't look like an invitation. Copy the "
                    + "whole message you were sent, or just the link in it."
            }
        }

        if let pasteNote {
            Text(pasteNote)
                .typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("account-paste-invite-note")
        }
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