import SwiftUI

/// The one screen between a tapped link and somebody else's music appearing in
/// your library.
///
/// design/FIREBASE.md §6A.5, and it is a deliberate small deviation from "no
/// special-casing": joining DOWNLOADS SOMEBODY ELSE'S COPIES of arrangements
/// into your own library, so it is not something to do silently on a tap. One
/// screen naming the set list and who owns it, with one button.
///
/// It is not a holding area. There is no "you've been invited" band, nothing
/// accumulates here, and declining leaves no trace -- the set list either
/// joins the one list or it does not.
struct JoinSetlistScreen: View {
    let inviteId: String
    var onBack: () -> Void
    var onJoined: (String) -> Void

    @EnvironmentObject var state: AppState
    @EnvironmentObject var shared: SharedSetlists
    @EnvironmentObject var signIn: SignIn

    @State private var joining = false
    @State private var trouble: String?

    var body: some View {
        Screen(title: "Join a set list", backLabel: "My library",
               onBack: onBack) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                if signIn.account == nil {
                    BandHeader("Sign in first")
                    PanelNote(text: "A set list somebody shares with you lives "
                              + "in your account, so you need one. Your own "
                              + "library keeps working without it.")
                        .padding(Theme.Metric.panelPadding)
                        .accessibilityIdentifier("join-needs-account")
                } else {
                    BandHeader("You've been sent a set list")
                    PanelNote(text: "Joining puts it in your set lists and "
                              + "downloads a copy of each arrangement in it. "
                              + "Your own music is not shared back.")
                        .padding(Theme.Metric.panelPadding)
                        .accessibilityIdentifier("join-explains")

                    PanelButton(title: joining ? "Joining…" : "Add to my set lists",
                                kind: .primary, identifier: "join-confirm") {
                        guard !joining else { return }
                        joining = true
                        Task {
                            defer { joining = false }
                            do {
                                let id = try await shared.claim(inviteId: inviteId)
                                state.pendingInvite = nil
                                shared.watchMemberships()
                                onJoined(id)
                            } catch {
                                // The reason. An expired link, a full set list
                                // and a withdrawn invitation are three
                                // different things and the messages say so.
                                trouble = error.localizedDescription
                            }
                        }
                    }

                    if let trouble {
                        Text(trouble)
                            .typeRole(.data).foregroundStyle(Theme.Ink.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, Theme.Metric.s16)
                            .accessibilityIdentifier("join-error")
                    }
                }
            }
        }
    }
}
