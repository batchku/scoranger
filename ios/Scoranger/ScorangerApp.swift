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
                    // warm up the interpreter so first render doesn't pay import cost
                    let started = await PythonEngine.shared.start()
                    print("SCORANGER-ENGINE start: \(started)")
                    #if DEBUG
                    let r = await PythonEngine.shared.call(op: "selftest")
                    print("SCORANGER-ENGINE selftest: \(r)")
                    // headless testing: adopt an OMR key dropped in Documents,
                    // then auto-ingest files from Documents/inbox through the
                    // same receiveFile path the share sheet uses (PDFs included)
                    let docs = FileManager.default
                        .urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let keyFile = docs.appending(path: "omr-key.txt")
                    if let key = try? String(contentsOf: keyFile, encoding: .utf8) {
                        KeychainStore.omrKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
                        try? FileManager.default.removeItem(at: keyFile)
                        print("SCORANGER-ENGINE omr key adopted")
                    }
                    let inbox = docs.appending(path: "inbox")
                    for f in (try? FileManager.default.contentsOfDirectory(
                        at: inbox, includingPropertiesForKeys: nil)) ?? []
                    where ["musicxml", "mxl", "xml", "mid", "midi", "pdf"]
                        .contains(f.pathExtension.lowercased()) {
                        print("SCORANGER-ENGINE inbox ingest: \(f.lastPathComponent)")
                        state.receiveFile(at: f)
                        try? FileManager.default.removeItem(at: f)
                    }
                    await state.refresh()
                    #endif
                }
        }
    }
}
