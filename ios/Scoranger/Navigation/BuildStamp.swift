import Foundation
import SwiftUI

/// What build this is, for a person holding the iPad.
///
/// Every hardware bug in this project has been diagnosed by asking "which build
/// are you on?" -- the Pencil selection failures, the subtract trap, the whistle
/// sizing. When the redesign dropped the version from the UI it took that with
/// it, so it is back, and in one place with one format.
enum BuildStamp {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "?"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    /// The commit the build was cut from, stamped in at build time. Absent in a
    /// build made outside the deploy script, in which case it is simply left
    /// out rather than shown as a lie.
    static var commit: String? {
        let sha = Bundle.main.object(forInfoDictionaryKey: "GitSHA") as? String
        guard let sha, !sha.isEmpty, sha != "$(GIT_SHA)" else { return nil }
        return sha
    }

    /// `v0.4.1 · b142 · a1b2c3d`
    static var short: String {
        (["v\(version)", "b\(build)"] + (commit.map { [$0] } ?? []))
            .joined(separator: " · ")
    }
}

/// The build stamp as a line of its own: centred, muted, out of the way.
///
/// Two places show it (#53) -- here on the library, and Settings → About --
/// and both read the same value out of Info.plist through `BuildStamp`, so
/// they cannot disagree about which build this is.
struct BuildStampLine: View {
    var body: some View {
        Text(BuildStamp.short)
            .typeRole(.data)
            .foregroundStyle(Theme.Ink.ink3.opacity(0.8))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, Theme.Metric.s24)
            .accessibilityIdentifier("build-stamp")
    }
}
