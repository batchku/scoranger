import Foundation

/// What an arrangement's artifact actually is, and what that allows.
///
/// Every version used to be engraved notation. The Newzik migration brings in
/// arrangements that are PDFs — scans and publisher editions — and the decision
/// was to keep them as they are and run OMR on the ones worth arranging. So a
/// scan is a first-class arrangement: it opens, it reads, and it takes Pencil
/// markup. What it cannot do is be edited, because selection, addresses and
/// every chat op are built from the engraved MEI, which only notation has.
///
/// Derived from the FILENAME rather than trusted from the manifest, so a
/// library written before kinds existed still answers correctly — the same
/// reason `workspace.artifact_kind` derives it on the engine side.
enum ScoreArtifact {
    enum Kind: String, Equatable {
        /// Engraved by Verovio from MusicXML: selectable, editable.
        case notation
        /// A PDF the reader brought in: readable and annotatable, not editable.
        case scan
        /// A photograph or a screenshot of a page. The SAME kind of thing as
        /// a scan in every way that matters -- readable, annotatable, not
        /// editable until OMR reads it -- and its own case only so the
        /// library can say which of the two a reader actually brought in.
        case image

        /// Whether an op can touch it. The question most callers are really
        /// asking, and the one that must not be spelled `== .scan` now that
        /// there are two kinds of scan.
        var isNotation: Bool { self == .notation }
    }

    /// Pictures of a page. Mirrors `workspace.IMAGE_SUFFIXES`; keep the two
    /// in step, and `check_image_scans.py` is what notices if they drift.
    static let imageSuffixes: Set<String> = ["jpg", "jpeg", "png", "heic"]

    /// Suffixes the engine can operate on. Mirrors `workspace.NOTATION_SUFFIXES`.
    static let notationSuffixes: Set<String> = ["musicxml", "xml", "mxl", "mid", "midi"]

    static func kind(ofFile file: String) -> Kind {
        let suffix = (file as NSString).pathExtension.lowercased()
        if notationSuffixes.contains(suffix) { return .notation }
        return imageSuffixes.contains(suffix) ? .image : .scan
    }

    /// A lasso needs a geometry index, and that comes from the MEI.
    static func allowsSelection(_ kind: Kind) -> Bool { kind == .notation }

    /// Every op is a music21 operation over notation.
    static func allowsEditing(_ kind: Kind) -> Bool { kind == .notation }

    /// Ink is keyed to a page, and a scan has pages like anything else. This is
    /// the whole point of bringing scans in before any OMR happens: the reader
    /// marks up the parts they play from on day one.
    static func allowsAnnotation(_ kind: Kind) -> Bool { true }

    /// A scan and a picture of a page are made editable the same way: OMR
    /// reads them into a notation version. Notation already is editable.
    static func canBeMadeEditable(_ kind: Kind) -> Bool { !kind.isNotation }

    /// The sentence under Make editable, naming what the artifact is.
    static func makeEditableNote(_ kind: Kind) -> String {
        let what = kind == .image ? "picture" : "PDF"
        return "This arrangement is a \(what). Reading it produces a notation "
            + "version you can transpose, select and ask about — the \(what) "
            + "stays as it is, so you can compare them."
    }

    /// What to say when someone asks for an edit that cannot happen yet.
    static func whyNotEditable() -> String {
        "This arrangement is a PDF. Run OMR on it to make it editable."
    }
}
