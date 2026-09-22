import Foundation
import UniformTypeIdentifiers

/// Which of the three import actions the reader asked for.
enum ImportKind: Equatable {

    /// What counts as a score file. Lives here rather than on a view because
    /// ScoreModel is the layer the unit tests can reach; ContentView still
    /// vends it under its own name for the callers that used it there.
    static let scoreTypes: [UTType] = ([
        UTType(filenameExtension: "musicxml"),
        UTType(filenameExtension: "mxl"),
        UTType(filenameExtension: "xml"),
        UTType(filenameExtension: "mid"),
        UTType(filenameExtension: "midi"),
        // ABC, which thesession.org publishes Irish traditional music as.
        // BOTH types, and the reason is worth knowing: `.abc` is already
        // taken. The system declares it as Alembic, Pixar's 3D scene cache,
        // so `UTType(filenameExtension: "abc")` resolves to `public.alembic`
        // and that is what a downloaded tune is tagged as. Offering only our
        // own type would grey every real tune out.
        UTType(filenameExtension: "abc"),
        UTType("com.scoranger.abc"),
    ].compactMap { $0 }) + [.pdf] + imageTypes

    /// The images a photographed score arrives as.
    ///
    /// 0.6.13 taught the IMPORT HANDLER about images -- they come in through
    /// share-in and the inbox and become an IMAGE-tagged piece -- and left
    /// this list alone. So the one route a reader actually looks for, Files,
    /// was the one route that greyed them out: Ali's own JPEG, a PNG and every
    /// screenshot on his iPad, unselectable beside the PDFs.
    ///
    /// The three the engine takes by name, AND the umbrella (§15).
    ///
    /// The umbrella was the open question: the engine imports four suffixes,
    /// so offering `public.image` would let a GIF or a TIFF past the grey and
    /// into a failed import. The ruling keeps the umbrella, and what makes it
    /// truthful is that the PIPELINE normalises rather than the picker
    /// narrowing -- `ScanImage.normalised` converts anything the engine will
    /// not take into something it will, at the one entry point both routes go
    /// through. So the picker can offer every picture the reader can see,
    /// because every picture the reader can see now imports.
    static let imageTypes: [UTType] = [.jpeg, .png, .heic, .image]

    /// One or more score files.
    case file
    /// A whole exported library: one folder per piece.
    case folder
    /// A collection to take arrangements out of.
    case book

    var contentTypes: [UTType] {
        switch self {
        case .file:   return Self.scoreTypes
        case .folder: return [.folder]
        case .book:   return [.pdf]
        }
    }

    /// A library arrives as many files; a folder and a book are one thing.
    var allowsMultiple: Bool { self == .file }
}

/// What the reader asked for, kept ACROSS the picker's dismissal.
///
/// This exists because of a bug that made Import Folder and Import Book do
/// nothing at all, on every build that had them. The presenter was driven by an
/// optional kind:
///
///     isPresented: Binding(get: { importKind != nil },
///                          set: { if !$0 { importKind = nil } })
///     ...
///     { result in let kind = importKind ?? .file
///
/// SwiftUI sets `isPresented` to false when the picker closes and runs that
/// setter BEFORE the completion handler. So the completion read a kind that had
/// already been cleared, fell back to `.file`, and handed a FOLDER to the
/// file-importing path -- which threw on a directory, into a `lastError` the
/// library never displayed. Import File worked only because `.file` was the
/// fallback that everything collapsed into.
///
/// So presentation and request are two different things here, and only
/// presentation is allowed to be cleared by dismissal.
struct ImportIntent: Equatable {
    /// The last thing asked for. Survives dismissal -- that is the point.
    private(set) var requested: ImportKind = .file
    /// Whether the picker should be on screen.
    private(set) var isPresented = false

    /// The reader tapped one of the three actions.
    mutating func ask(for kind: ImportKind) {
        requested = kind
        isPresented = true
    }

    /// The picker closed. What was ASKED FOR is deliberately kept: the
    /// completion handler has not run yet.
    mutating func dismissed() {
        isPresented = false
    }
}
