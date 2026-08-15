import SwiftUI

@main
struct ScorangerApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .task {
                    // warm up the interpreter so first render doesn't pay import cost
                    let started = await PythonEngine.shared.start()
                    print("SCORANGER-ENGINE start: \(started)")
                    #if DEBUG
                    let r = await PythonEngine.shared.call(op: "selftest")
                    print("SCORANGER-ENGINE selftest: \(r)")
                    // auto-import files dropped in Documents/inbox (headless testing)
                    let inbox = FileManager.default
                        .urls(for: .documentDirectory, in: .userDomainMask)[0]
                        .appending(path: "inbox")
                    for f in (try? FileManager.default.contentsOfDirectory(
                        at: inbox, includingPropertiesForKeys: nil)) ?? []
                    where ["musicxml", "mxl", "xml", "mid", "midi"]
                        .contains(f.pathExtension.lowercased()) {
                        let name = f.deletingPathExtension().lastPathComponent
                        let slug = try? await state.local.importScore(fileURL: f, name: name)
                        print("SCORANGER-ENGINE inbox import: \(slug ?? "failed") from \(f.lastPathComponent)")
                        try? FileManager.default.removeItem(at: f)
                    }
                    await state.refresh()
                    #endif
                }
        }
    }
}
