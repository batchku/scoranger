import Foundation

/// A private copy of a file that has just arrived, made OFF the main thread.
///
/// Every import path takes one before it hands the file to the engine: the
/// sender's grant does not outlive the call, and the engine needs a path it
/// owns. They all ran `copyItem` on the main actor (AppState is @MainActor,
/// and the Tasks they ran in inherited it). Within one volume that is a clone
/// and costs nothing; from another volume a 28 MB tunebook is a hitch the
/// reader sees, and it was found diagnosing the 0.14.0 gate (0.14.1).
///
/// The caller still opens and closes the security scope around the await: the
/// scope is the caller's, and it lasts across the suspension.
enum IncomingCopy {
    /// Copy `source` to `destination`, replacing whatever is there.
    static func make(_ source: URL, at destination: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let files = FileManager.default
            try? files.removeItem(at: destination)
            try files.copyItem(at: source, to: destination)
        }.value
    }
}
