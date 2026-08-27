import Foundation

/// Getting a score out of the app.
///
/// Three formats, and they do NOT share a source:
///
/// - **MusicXML** and **MIDI** come from the engine bridge. A version artifact
///   already IS MusicXML, so that one is a file copy rather than a re-write --
///   re-serialising would risk changing bytes the user never asked to change.
/// - **PDF is engraved here, in Swift**, by the same `VerovioRenderer` that
///   draws the page. That is not an implementation detail: chord-symbol
///   adjustments and whistle fingerings are applied in the Swift render pass,
///   so a PDF built anywhere else would not match what the user is looking at.
///   `bridge.py` refuses a PDF request for exactly this reason.
enum ScoreExport {

    enum Format: String, CaseIterable {
        case musicxml, midi, pdf

        var label: String {
            switch self {
            case .musicxml: return "MusicXML"
            case .midi:     return "MIDI"
            case .pdf:      return "PDF"
            }
        }

        /// What it is for, in the user's terms rather than the format's.
        var detail: String {
            switch self {
            case .musicxml: return "Open in another notation program"
            case .midi:     return "Play or import into a DAW"
            case .pdf:      return "Print or read anywhere"
            }
        }

        var fileExtension: String {
            switch self {
            case .musicxml: return "musicxml"
            case .midi:     return "mid"
            case .pdf:      return "pdf"
            }
        }

        /// True where the file is engraved in Swift rather than fetched from
        /// the bridge. Only PDF, and see the type comment for why.
        var isRenderedOnDevice: Bool { self == .pdf }
    }

    /// Filesystem-hostile characters, plus the ones Files and Mail dislike.
    private static let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")

    /// The longest a name may be before the extension, leaving room for it.
    private static let maxStem = 100

    /// What the exported file is called.
    ///
    /// The arrangement's own title, because the file leaves the app: "v003.
    /// musicxml" tells nobody anything once it is sitting in Files. A PINNED
    /// version is named too, since that is part of what the file is; the latest
    /// version is not, because that is simply "the arrangement".
    static func filename(title: String, version: String?, format: Format) -> String {
        var stem = title
            .components(separatedBy: forbidden)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if stem.isEmpty { stem = "score" }
        if let version, !version.isEmpty { stem += " \(version)" }
        if stem.count > maxStem { stem = String(stem.prefix(maxStem)) }
        return "\(stem).\(format.fileExtension)"
    }
}

/// A `URL` the `.sheet(item:)` modifier can key on.
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
