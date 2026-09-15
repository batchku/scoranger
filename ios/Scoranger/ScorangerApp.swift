import SwiftUI

@main
struct ScorangerApp: App {
    @StateObject private var state = AppState()
    /// The account. Constructed at launch and INERT until
    /// somebody presses a sign-in button: constructing it does
    /// not configure Firebase (design/FIREBASE.md §0.2).
    @StateObject private var signIn = SignIn()
    /// The shared set lists. Also inert until somebody signs in: every method
    /// on it returns early while `FirebaseApp` has not been configured, so a
    /// signed-out launch touches no network and starts no listener (§0.2).
    @StateObject private var shared = SharedSetlists()

    /// The one moment a test's reset can be total.
    ///
    /// `@AppStorage` reads its value as the property wrapper is constructed,
    /// and `AppState` is constructed with this struct, so anything later --
    /// the old reset ran from `RootView.task` -- clears keys whose values have
    /// already been handed out. Here, nothing has read a default yet.
    init() {
        TestReset.wipe()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .environmentObject(signIn)
                .environmentObject(shared)
                // Paper & Clay is a single fixed light palette: every surface is
                // a hard hex value with no dark variant. Left to follow the
                // system, dark mode kept the light surfaces but handed every
                // unstyled Text and TextField a white foreground -- which is
                // how the metadata fields in the arrangement sheet ended up
                // with invisible text. One palette, one appearance.
                .preferredColorScheme(.light)
                .onOpenURL { url in
                    // An invitation link comes in the same door as a
                    // `.scorbundle` from AirDrop and a sign-in callback, so it
                    // is recognised positively and everything else falls
                    // through to the file path unchanged.
                    // Both link forms land here: the https universal link
                    // people actually send, and the scoranger:// fallback.
                    // `inviteId(in:)` recognises either and refuses anything
                    // else, so an AirDropped .scorbundle still reaches the
                    // import path unchanged.
                    if let invite = SharedInviteLink.inviteId(in: url) {
                        state.pendingInvite = invite
                    } else {
                        state.receiveFile(at: url)
                    }
                }
                .task {
                    // Installs a CLOSURE and calls nothing. The closure's own
                    // body is what guards on a configured app, so this reaches
                    // no cloud at launch and returns nil for every reader who
                    // never signs in -- which is what lets it be installed
                    // here rather than at first sign-in, where a signed-in
                    // reader who never opens Settings would be missed.
                    OMRIdentity.install(into: state)
                    state.migrateStaleOMRURL()
                    state.prepareDocumentsFolders()
                    // The mixer window opens where it was left, and in the
                    // state it was left in (MIXER_WINDOW.md §5, §1.3).
                    // warm up the interpreter so first render doesn't pay import cost
                    let started = await PythonEngine.shared.start()
                    print("SCORANGER-ENGINE start: \(started)")
                    #if DEBUG
                    let r = await PythonEngine.shared.call(op: "selftest")
                    print("SCORANGER-ENGINE selftest: \(r)")
                    // headless testing: adopt an OMR key dropped in Documents
                    // (inbox ingestion is a release feature now — see scanInbox)
                    let keyFile = FileManager.default
                        .urls(for: .documentDirectory, in: .userDomainMask)[0]
                        .appending(path: "omr-key.txt")
                    if let key = try? String(contentsOf: keyFile, encoding: .utf8) {
                        KeychainStore.omrKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
                        try? FileManager.default.removeItem(at: keyFile)
                        print("SCORANGER-ENGINE omr key adopted")
                    }
                    #endif
                    await state.seedLibraryIfEmpty()
                    // the imported library carries no metadata of its own
                    await state.applyBundledMetadataIfNeeded()
                    await state.refresh()
                    // needs a manifest in hand, so it follows the first refresh
                    await state.migrateSeededSetlistName()
                    #if DEBUG
                    await state.seedMultiStepTurnIfRequested()
                    // after the library seed, and after the refresh that gives
                    // it a manifest to check itself against
                    await state.seedScanArrangementIfRequested()
                    // last: it names the arrangements the seeds above made
                    await state.seedOMRQueueIfRequested()
                    #endif
                }
        }
    }
}
