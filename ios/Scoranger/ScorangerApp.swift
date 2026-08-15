import SwiftUI

@main
struct ScorangerApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .task {
                    #if DEBUG
                    let started = await PythonEngine.shared.start()
                    print("SCORANGER-ENGINE start: \(started)")
                    let r = await PythonEngine.shared.call(op: "selftest")
                    print("SCORANGER-ENGINE selftest: \(r)")
                    #endif
                }
        }
    }
}
