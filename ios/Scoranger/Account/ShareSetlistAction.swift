import SwiftUI
import UIKit

/// What the share button on a set list row does.
///
/// design/FIREBASE.md §6A.4. Three states, and the middle one is why this is a
/// type rather than a closure: promotion is network work that can take a while
/// and can fail, and a share button that appears to do nothing is how the last
/// three builds felt.
@MainActor
final class ShareSetlistAction: ObservableObject {

    enum State: Equatable {
        case idle
        /// Promoting: uploading a copy of each arrangement. `done` of `total`.
        case working(done: Int, total: Int)
        /// A link, ready to hand to the iOS share sheet.
        case ready(URL, name: String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    /// Share the set list with this slug.
    ///
    /// Already shared: mints a fresh link and returns immediately -- no
    /// re-upload, because the entries are already there. Not yet shared:
    /// promotes in place first (§6A.1).
    ///
    /// `signedIn` is passed in rather than read here so this type stays free
    /// of Firebase; `check_signed_out.py` keeps those calls inside `Account/`
    /// and this file has no business configuring anything.
    func share(setlist: SetlistDoc, arrangements: [ScoreDoc],
               shared: SharedSetlists, state appState: AppState,
               signedIn: Bool) async {
        guard signedIn else {
            // §6A.2: the button STAYS for a signed-out reader and explains
            // itself. It does not vanish, because a control that appears only
            // for some accounts teaches nobody where sharing lives.
            state = .failed("Sign in to share a set list. Settings › Account.")
            return
        }
        state = .working(done: 0, total: setlist.arrangements.count)
        do {
            let url = try await shared.promote(
                setlist: setlist,
                arrangements: arrangements,
                payload: { slug in try await appState.sharePayload(for: slug) },
                bind: { shareId, ownerUid in
                    _ = try await appState.local.call(
                        op: "bind-setlist-share",
                        args: ["setlist": setlist.slug,
                               "shareId": shareId, "ownerUid": ownerUid])
                    await appState.refresh()
                },
                progress: { [weak self] done, total in
                    self?.state = .working(done: done, total: total)
                })
            state = .ready(url, name: setlist.name)
        } catch {
            // The reason, not "something went wrong". Promotion fails for
            // reasons a person can act on -- offline, signed out, a set list
            // somebody else already shares.
            state = .failed(error.localizedDescription)
        }
    }

    func clear() { state = .idle }

    /// The message the share sheet carries.
    ///
    /// The https link, because this is going into Messages or Mail and a
    /// custom scheme arrives there as dead text -- which was the whole
    /// problem. One sentence of context so the recipient knows what they are
    /// being sent before they tap a link.
    static func message(name: String, url: URL) -> String {
        """
        Join my set list "\(name)" in Scoranger:
        \(url.absoluteString)
        """
    }
}

/// `UIActivityViewController`, as a SwiftUI sheet.
///
/// The standard iOS share sheet, which is what Ali asked for: "generates a
/// link I can send via sms or email or other normal iOS ways." Not a
/// hand-rolled list of destinations -- the system sheet already knows every
/// app that can take a link, including ones installed after this shipped.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController,
                               context: Context) {}
}
