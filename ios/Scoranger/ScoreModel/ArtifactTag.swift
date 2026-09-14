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
struct ArtifactHolding: OptionSet, Hashable {
    let rawValue: Int
    init(rawValue: Int) { self.rawValue = rawValue }

    /// A PDF the reader brought in.
    static let pdf = ArtifactHolding(rawValue: 1 << 0)
    /// A photograph or screenshot of a page.
    static let image = ArtifactHolding(rawValue: 1 << 1)
    /// Engraved notation.
    static let notation = ArtifactHolding(rawValue: 1 << 2)

    /// What an arrangement looks like AFTER OMR: the scan stays so it can be
    /// compared against, and the notation is what is editable. Kept as a name
    /// because three call sites and a dozen tests say `.both`, and it means
    /// exactly what it always did.
    static let both: ArtifactHolding = [.pdf, .notation]

    /// A SET rather than three cases, because the cases stopped being
    /// mutually exclusive the moment images arrived. Enumerating them would
    /// be seven cases to write and seven more the next time something is
    /// importable; composing them is the same fact with no arithmetic.
    ///
    /// Whether anything under this tag can be selected, transposed or played.
    var hasNotation: Bool { contains(.notation) }

    /// Whether everything here is a scan of some sort. This is the question
    /// the library row asks to draw its scan treatment, and it used to be
    /// spelled `holding == .pdf` -- which an image-only arrangement fails
    /// while being exactly as much of a scan.
    var isScanOnly: Bool { !isEmpty && !hasNotation }
}

enum ArtifactTag {

    /// The words on the tag. Upper case, because these are chips and every
    /// other chip in the library is (`UNFILED`, `OMR DRAFT`, `1 SOURCE`).
    ///
    /// "MUSICXML" and not "NOTATION": the reader asked for PDF vs MusicXML in
    /// those words, and MusicXML is what the engine actually stores.
    static func label(_ holding: ArtifactHolding) -> String {
        words(holding).joined(separator: " + ")
    }

    /// In the order a reader met them: what they brought in, then what the
    /// app made of it. "MUSICXML + PDF" would read as though the notation
    /// came first.
    private static func words(_ holding: ArtifactHolding) -> [String] {
        var out: [String] = []
        if holding.contains(.pdf) { out.append("PDF") }
        if holding.contains(.image) { out.append("IMAGE") }
        if holding.contains(.notation) { out.append("MUSICXML") }
        return out
    }

    /// A single artifact kind as a tag, for the score view's own marker: what
    /// is ON SCREEN is one version, and one version is one kind.
    static func label(_ kind: ScoreArtifact.Kind) -> String {
        label(holding(for: kind))
    }

    static func holding(for kind: ScoreArtifact.Kind) -> ArtifactHolding {
        switch kind {
        case .notation: return .notation
        case .image:    return .image
        case .scan:     return .pdf
        }
    }

    /// What a set of files holds. Nil when there are none -- an arrangement
    /// with no versions has nothing to say about itself, and a tag reading
    /// "PDF" over an empty arrangement would be a lie.
    static func holding(files: [String]) -> ArtifactHolding? {
        var seen: ArtifactHolding = []
        for file in files where !file.isEmpty {
            seen.insert(holding(for: ScoreArtifact.kind(ofFile: file)))
        }
        return seen.isEmpty ? nil : seen
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
    /// One chip per fact, never a compound one: the reader is answering two
    /// questions and two answers read faster than a phrase joining them.
    ///
    /// Notation takes the accent chip -- clay is this app's "live", and
    /// notation is the half that can actually be worked on.
    static func chips(for holding: ArtifactHolding) -> [LibraryRow.Chip] {
        words(holding).map { word in
            .init(text: word, kind: word == "MUSICXML" ? .count : .plain)
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
        kind.isNotation ? "editable" : "not editable"
    }
}
