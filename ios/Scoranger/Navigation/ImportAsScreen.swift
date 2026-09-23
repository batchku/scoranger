import SwiftUI

/// What a file shared into the app should become (0.14.0 §1).
///
/// Three choices, as three big buttons, because the reader has just come from
/// another app with something in hand and the question is the only thing on
/// the page: a NEW PIECE (what every share did before), a NEW ARRANGEMENT in a
/// piece already in the library, or a NEW BOOK. The second opens its list of
/// pieces in place, a choice made on the page rather than on a sheet
/// (NAV_MODAL_FREE_0.4.2 §1).
///
/// A book is a PDF, so the third is offered for one PDF and said to be
/// unavailable otherwise -- disabled with its reason, not hidden, so a reader
/// who shared a MusicXML file hoping for a book is told why not.
struct ImportAsScreen: View {
    @EnvironmentObject var state: AppState
    var onBack: () -> Void
    var onChosen: (ImportChoice) -> Void

    @State private var choosingPiece = false
    @State private var filter = ""

    private var offer: AppState.ImportOffer? { state.importOffer }

    var body: some View {
        Screen(title: "Import as", backLabel: "Cancel",
               subtitle: offer?.summary, onBack: onBack) {
            VStack(alignment: .leading, spacing: Theme.Metric.s12) {
                if offer == nil {
                    PanelNote(text: "Nothing is waiting to be imported.")
                } else {
                    choice(title: "New piece",
                           detail: "A piece named after the file, with this as its "
                                 + "first arrangement. A piece of that name already "
                                 + "in the library is used instead.",
                           glyph: "music.note.list", id: "import-as-new-piece") {
                        onChosen(.newPiece)
                    }
                    choice(title: "New arrangement in an existing piece",
                           detail: "Filed under a piece you pick.",
                           glyph: "square.stack", id: "import-as-existing-piece",
                           open: choosingPiece) {
                        choosingPiece.toggle()
                    }
                    if choosingPiece { pieceList }
                    choice(title: "New book",
                           detail: offer?.canBeBook == true
                               ? "A collection of tunes, read one at a time or taken "
                                 + "out as pieces. Its tunes are found for you to check."
                               : "Only a single PDF can be a book.",
                           glyph: "books.vertical", id: "import-as-new-book") {
                        onChosen(.newBook)
                    }
                    .disabled(offer?.canBeBook != true)
                }
            }
            .padding(Theme.Metric.pageSide)
            .padding(.bottom, Theme.Metric.s32)
        }
    }

    private func choice(title: String, detail: String, glyph: String, id: String,
                        open: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Theme.Metric.s16) {
                Image(systemName: glyph)
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.Accent.clayStrong)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: Theme.Metric.s4) {
                    Text(title).typeRole(.titleS).foregroundStyle(Theme.Ink.ink)
                    Text(detail).typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if open {
                    Image(systemName: "chevron.up").foregroundStyle(Theme.Ink.ink3)
                }
            }
            .padding(Theme.Metric.s20)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .background(open ? Theme.Accent.clayTint : Theme.Surface.panel)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rInner))
            // the panel fill is a shade off the page; the edge is what makes
            // each choice read as one thing to press
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metric.rInner)
                    .strokeBorder(open ? Theme.Accent.clayBorder : Theme.Ink.ink3.opacity(0.35),
                                  lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ChoiceStyle())
        .accessibilityIdentifier(id)
    }

    private var pieces: [PieceDoc] {
        let all = state.manifest?.pieces ?? []
        let wanted = filter.trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(wanted) }
    }

    @ViewBuilder
    private var pieceList: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelField(placeholder: "Find a piece", text: $filter)
                .accessibilityIdentifier("import-as-piece-filter")
                .padding(.bottom, Theme.Metric.s8)
            if pieces.isEmpty {
                PanelNote(text: (state.manifest?.pieces ?? []).isEmpty
                          ? "There are no pieces in the library yet."
                          : "No piece is called that.")
            }
            ForEach(pieces) { piece in
                ScreenRow(title: piece.name,
                          value: "\(piece.arrangements.count)",
                          leads: false,
                          identifier: "import-as-piece-\(piece.slug)") {
                    onChosen(.existingPiece(piece.slug))
                }
            }
        }
        .padding(.leading, 56)
    }
}

/// The big buttons dim while pressed and when disabled, as PanelButton does.
private struct ChoiceStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.42)
    }
}
