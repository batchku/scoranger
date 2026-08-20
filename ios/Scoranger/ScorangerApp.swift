import SwiftUI

@main
struct ScorangerApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .onOpenURL { url in
                    state.receiveFile(at: url)
                }
                .task {
                    state.migrateStaleOMRURL()
                    state.prepareDocumentsFolders()
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
                    await state.refresh()
                }
        }
    }
}
