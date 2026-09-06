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
    ].compactMap { $0 }) + [.pdf] + imageTypes

    /// The images a photographed score arrives as.
    ///
    /// 0.6.13 taught the IMPORT HANDLER about images -- they come in through
    /// share-in and the inbox and become an IMAGE-tagged piece -- and left
    /// this list alone. So the one route a reader actually looks for, Files,
    /// was the one route that greyed them out: Ali's own JPEG, a PNG and every
    /// screenshot on his iPad, unselectable beside the PDFs.
    ///
    /// EXACTLY the three the pipeline takes, and deliberately not the
    /// `public.image` umbrella. The engine imports four suffixes
    /// (`workspace.IMAGE_SUFFIXES`, and `ScoreArtifact.imageSuffixes` beside
    /// it); an umbrella would make a GIF or a TIFF selectable and then refuse
    /// it after the reader had chosen it, which is the same bug wearing better
    /// clothes. `ImportContentTypeTests` asserts the relationship in both
    /// directions -- nothing the app takes is greyed out, and nothing offered
    /// would be refused -- so widening the engine is what lets this widen.
    static let imageTypes: [UTType] = [.jpeg, .png, .heic]

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
