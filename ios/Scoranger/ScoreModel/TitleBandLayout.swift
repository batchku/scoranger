import CoreGraphics

/// How tall the title switcher band is, and what its version rows say.
///
/// The band is an inline reveal over the score: it pushes the music down
/// rather than floating on it, which is the whole reason it is a band. That
/// only works if it is the size of what is in it. It was taking half the
/// screen for five rows -- the divider between its two columns was a rectangle
/// with a width and no height, and a rectangle like that grows to whatever it
/// is offered, taking the band with it.
enum TitleBandLayout {

    /// What the band is showing.
    ///
    /// It used to show both columns at once, whichever control opened it -- so
    /// tapping "3 versions" put a list of OTHER PIECES on screen next to the
    /// versions, and the reader had to find the right half of a dropdown they
    /// had asked a specific question of (0.6.3 #8).
    ///
    /// Both lists survive; each has its own way in. The title block, which
    /// names the arrangement, opens the arrangements of the piece; the
    /// versions trigger, which counts versions, opens the versions.
    enum Mode: Equatable {
        case arrangements
        case versions
        /// Which set lists this arrangement is in, with a box per set list
        /// (0.6.11 #1). A third mode on this band rather than a second kind of
        /// dropdown on the score: the band already knows how tall to be, when
        /// to scroll, and how to get out of the way, and a floating panel
        /// beside it would be a second answer to all three.
        case setlists

        var heading: String {
            switch self {
            case .arrangements: return "Arrangements"
            case .versions:     return "Versions"
            case .setlists:     return "Set lists"
            }
        }
    }

    static let rowHeight: CGFloat = 33
    static let headerHeight: CGFloat = 24

    /// Never more than this much of the score. Past it the band scrolls
    /// internally: the music stays readable behind the thing you opened to
    /// change it.
    static let maxFraction: CGFloat = 0.4

    /// The band's natural height: the taller of its two columns.
    ///
    /// Kept for the two-column case, which nothing renders any more -- and
    /// kept because it is what `contentHeight(mode:)` is measured against: one
    /// column can never be taller than the pair it came from.
    static func contentHeight(arrangements: Int, versions: Int,
                              hasAllVersionsRow: Bool) -> CGFloat {
        max(contentHeight(mode: .arrangements, rows: arrangements,
                          hasAllVersionsRow: false),
            contentHeight(mode: .versions, rows: versions,
                          hasAllVersionsRow: hasAllVersionsRow))
    }

    /// One column's natural height: its heading plus its rows.
    ///
    /// At least one row is counted even for an empty list, so an empty band is
    /// a band with a heading and a gap rather than a 24pt sliver nobody can
    /// tell opened.
    static func contentHeight(mode: Mode, rows: Int,
                              hasAllVersionsRow: Bool) -> CGFloat {
        let extra = (mode == .versions && hasAllVersionsRow) ? 1 : 0
        return headerHeight + CGFloat(max(rows, 1) + extra) * rowHeight
    }

    /// What it is actually given, capped against the space available.
    static func height(content: CGFloat, available: CGFloat) -> CGFloat {
        guard available > 0 else { return content }
        return min(content, available * maxFraction)
    }

    static func scrolls(content: CGFloat, available: CGFloat) -> Bool {
        available > 0 && content > available * maxFraction
    }

    /// What a version row says.
    ///
    /// It said "v003", "v002", "v001" -- ids and nothing else, so switching
    /// version while reading was a guess. The prompt that made the version is
    /// what a person remembers; the op is the fallback for versions made from
    /// the CLI, and the id is still shown beside it because it is what the
    /// rest of the app calls this thing.
    /// One rule, kept in `VersionLabel`: what was ASKED for, and failing that
    /// what HAPPENED -- never the engine's name for the operation. This
    /// returned the raw op, so the band read "omr" and "bulk-import" beside
    /// the versions it was offering to switch to.
    static func versionLabel(prompt: String?, op: String) -> String {
        VersionLabel.text(op: op, prompt: prompt)
    }
}
