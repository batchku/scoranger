import Foundation

/// What a piece or an arrangement HOLDS: a PDF, engraved notation, or both.
///
/// The reader could not tell a scan from an engraving anywhere in the library.
/// It is the single most consequential fact about an arrangement -- a PDF
/// cannot be selected, transposed, asked about or played, and the only way to
/// find out was to open it and watch the controls fail.
///
/// Derived from the version FILENAMES through `ScoreArtifact.kind(ofFile:)`,
/// which is the same answer the score view already gives itself
/// (`AppState.displayedArtifact`). One notion of what an artifact is, three
/// places that show it.
enum ArtifactHolding: Equatable {
    /// PDFs only: nothing here has been read into notation yet.
    case pdf
    /// Engraved notation only.
    case notation
    /// Both, which is what an arrangement looks like AFTER OMR: the PDF stays
    /// so it can be compared against, and the notation is what is editable.
    case both

    /// Whether anything under this tag can be selected, transposed or played.
    var hasNotation: Bool { self != .pdf }
}

enum ArtifactTag {

    /// The words on the tag. Upper case, because these are chips and every
    /// other chip in the library is (`UNFILED`, `OMR DRAFT`, `1 SOURCE`).
    ///
    /// "MUSICXML" and not "NOTATION": the reader asked for PDF vs MusicXML in
    /// those words, and MusicXML is what the engine actually stores.
    static func label(_ holding: ArtifactHolding) -> String {
        switch holding {
        case .pdf:      return "PDF"
        case .notation: return "MUSICXML"
        case .both:     return "PDF + MUSICXML"
        }
    }

    /// A single artifact kind as a tag, for the score view's own marker: what
    /// is ON SCREEN is one version, and one version is one kind.
    static func label(_ kind: ScoreArtifact.Kind) -> String {
        label(holding(for: kind))
    }

    static func holding(for kind: ScoreArtifact.Kind) -> ArtifactHolding {
        kind == .notation ? .notation : .pdf
    }

    /// What a set of files holds. Nil when there are none -- an arrangement
    /// with no versions has nothing to say about itself, and a tag reading
    /// "PDF" over an empty arrangement would be a lie.
    static func holding(files: [String]) -> ArtifactHolding? {
        var sawNotation = false
        var sawScan = false
        for file in files where !file.isEmpty {
            switch ScoreArtifact.kind(ofFile: file) {
            case .notation: sawNotation = true
            case .scan:     sawScan = true
            }
        }
        switch (sawNotation, sawScan) {
        case (true, true):   return .both
        case (true, false):  return .notation
        case (false, true):  return .pdf
        case (false, false): return nil
        }
    }

    /// One arrangement, across its whole history.
    ///
    /// The HISTORY and not just the latest version, deliberately: a scan that
    /// has been OMR'd holds both, and saying only "MUSICXML" would hide the
    /// PDF the reader imported and still wants to compare against.
    static func holding(of score: ScoreDoc) -> ArtifactHolding? {
        holding(files: score.versions.map(\.file))
    }

    /// A piece, across every arrangement filed under it. This is the piece-level
    /// tag: "what does this tune hold in my library".
    static func holding(ofScores scores: [ScoreDoc]) -> ArtifactHolding? {
        holding(files: scores.flatMap { $0.versions.map(\.file) })
    }

    /// The chips a row shows for a holding.
    ///
    /// TWO chips for `both`, not one compound one: the reader is checking "can
    /// I edit this" and "do I still have the original", and two answers read
    /// faster than a phrase joining them. Notation takes the accent chip --
    /// clay is this app's "live" -- and the PDF takes the plain one.
    static func chips(for holding: ArtifactHolding) -> [LibraryRow.Chip] {
        switch holding {
        case .pdf:      return [.init(text: "PDF", kind: .plain)]
        case .notation: return [.init(text: "MUSICXML", kind: .count)]
        case .both:     return [.init(text: "PDF", kind: .plain),
                                .init(text: "MUSICXML", kind: .count)]
        }
    }

    /// The chips for a row, or none where there is nothing to say.
    static func chips(files: [String]) -> [LibraryRow.Chip] {
        holding(files: files).map(chips(for:)) ?? []
    }

    /// What the score view's top-left marker says, and what it means.
    ///
    /// The marker states the CONSEQUENCE as well as the format, because "PDF"
    /// alone does not tell a reader why the pencil selects nothing.
    static func markerDetail(_ kind: ScoreArtifact.Kind) -> String {
        kind == .notation ? "editable" : "not editable"
    }
}
