import CoreGraphics

/// What the score's top bar shows at a given width, and in what order things
/// yield when there is not enough of it.
///
/// #60: on a phone the bar had no ✕ at all. The version count added beside the
/// title pushed it out, and with no ✕ there is no way to leave the score --
/// a dead end, on the one screen size where there is no other route back. It
/// was present in build 149 and gone in 152.
///
/// The fix is not to shorten one control. It is to say ONCE what the bar gives
/// up first, so the next thing added to it cannot squeeze out the way out:
///
///   1. ✕ close          FIXED. Never yields. Without it the score is a trap.
///   2. Edit, Ask, …     the actions the score view exists for
///   3. transport toggle optional -- the Options screen carries the same
///                       switch, so nothing becomes unreachable when it goes
///   4. layout control   three cells, then two
///   5. the title        flexible: it truncates, it does not disappear
///   6. version count    optional -- the title block opens the same band, so
///                       nothing becomes unreachable when it goes
///   7. the mode chip    optional, and the first to go -- the Edit button's
///                       own active state still states the mode
///
/// Nothing above the line an item sits on is ever sacrificed for it.
enum ScoreBarLayout {
    struct Fit: Equatable {
        /// The "N versions" dropdown trigger.
        var showsVersions: Bool
        /// The "Pencil: …" chip under the title.
        var showsModeChip: Bool
        /// Cells in the layout control: 3 (page/spread/continuous) or 2
        /// (page/continuous -- a spread across a phone is two thumbnails).
        var layoutCells: Int
        /// The "Show transport" toggle, beside the layout cells (0.6.3 #6).
        ///
        /// Optional, and the Options screen keeps the same switch: a bar too
        /// narrow to seat it must not be a bar with no way to turn playback's
        /// chrome back on. Dropping a SHORTCUT is allowed here; dropping a
        /// feature is not.
        var showsTransportToggle: Bool = true
        /// The "#N" badge: which arrangement of the piece this is.
        var showsNumeral: Bool = true
        /// The second line under the title: piece name and version.
        ///
        /// Costs no WIDTH -- it is a second line in the same column -- so it is
        /// not in `fits`. It goes on a narrow bar anyway: two truncated lines
        /// read worse than one whole one, and its piece name largely repeats
        /// the title while its version is what the dropdown behind the title
        /// says.
        var showsSubtitle: Bool = true

        /// Whether the title should EXPAND into the bar's slack rather than
        /// sit centred between two spacers.
        ///
        /// A SwiftUI Text yields before a Spacer does, so on a narrow bar the
        /// title collapsed to an ellipsis while the spacers kept their space.
        /// Expanding is the fix that cannot overflow -- unlike a hard minimum,
        /// which pushed the ✕ off the bar (#60, reproduced while fixing #62).
        var titleExpands: Bool { !showsNumeral }
    }

    /// Measured widths of the bar's parts, so the arithmetic below is legible
    /// rather than a table of magic numbers.
    static let closeWidth: CGFloat = 34
    static let actionWidth: CGFloat = 34          // Edit, Ask, …
    static let gap: CGFloat = 8
    static let padding: CGFloat = 24              // s12 either side
    static let threeCells: CGFloat = 40 * 3 + 2   // cells plus their dividers
    static let twoCells: CGFloat = 40 * 2 + 1
    static let versionsWidth: CGFloat = 110
    /// The transport toggle and the gap before it.
    static let transportWidth: CGFloat = 34 + 8
    static let modeChipWidth: CGFloat = 90
    static let numeralWidth: CGFloat = 40
    /// Less than this and the title is not a title any more.
    ///
    /// 90, not 100: the narrowest common iPhone is 375pt, and the essentials
    /// plus two layout cells plus 100 came to 381 -- six points over. A hard
    /// minimum that does not fit is how something gets pushed off the bar, and
    /// that is #60.
    static let titleMinimum: CGFloat = 90

    /// The bar's fixed furniture: the way out, three actions, and their gaps.
    static var essentials: CGFloat {
        padding + closeWidth + actionWidth * 3 + gap * 5
    }

    static func fit(barWidth: CGFloat) -> Fit {
        let everything = Fit(showsVersions: true, showsModeChip: true, layoutCells: 3)
        // Unmeasured: show everything rather than flashing a stripped bar on
        // the first frame and filling it in afterwards.
        guard barWidth > 0 else { return everything }

        let forAll = essentials + threeCells + versionsWidth + modeChipWidth
            + transportWidth + titleMinimum
        if barWidth >= forAll { return everything }

        // The chip goes first: the Edit button already states the mode.
        let withoutChip = forAll - modeChipWidth
        if barWidth >= withoutChip {
            return Fit(showsVersions: true, showsModeChip: false, layoutCells: 3)
        }
        // Then the version count. The title block opens the same dropdown, so
        // versions stay REACHABLE -- this drops a shortcut, never a feature.
        let withoutVersions = withoutChip - versionsWidth
        if barWidth >= withoutVersions {
            return Fit(showsVersions: false, showsModeChip: false, layoutCells: 3)
        }
        // Then the transport toggle. Its switch is still in Options, and the
        // transport reveals itself on the first playable arrangement anyway
        // (TransportReveal) -- so a phone loses a shortcut and nothing else.
        let withoutTransport = withoutVersions - transportWidth
        if barWidth >= withoutTransport {
            return Fit(showsVersions: false, showsModeChip: false, layoutCells: 3,
                       showsTransportToggle: false)
        }
        // Then the spread cell, which is the one a narrow screen cannot use.
        let twoCellFit = Fit(showsVersions: false, showsModeChip: false, layoutCells: 2,
                             showsTransportToggle: false)
        if fits(twoCellFit, in: barWidth) { return twoCellFit }

        // Then the title's COMPANIONS, so the title itself can stay readable.
        // #62: with the version count already yielded, the title block is the
        // only route to the version dropdown -- and it had collapsed to
        // "#1 S… ⌄", which nobody reads as a control. The subtitle goes first
        // (its piece name largely repeats the title, and its version is what
        // the dropdown behind the title says), then the numeral.
        //
        // They yield rather than the title being given a hard minimum: forcing
        // a width here pushed the ✕ off the bar entirely, which is #60.
        let withoutSubtitle = Fit(showsVersions: false, showsModeChip: false,
                                  layoutCells: 2, showsTransportToggle: false,
                                  showsSubtitle: false)
        if fits(withoutSubtitle, in: barWidth) { return withoutSubtitle }
        return Fit(showsVersions: false, showsModeChip: false, layoutCells: 2,
                   showsTransportToggle: false,
                   showsNumeral: false, showsSubtitle: false)
    }

    /// Whether a bar this wide can seat everything it is being asked to.
    /// Used by the test that guards the phone.
    static func fits(_ fit: Fit, in width: CGFloat) -> Bool {
        var needed = essentials + titleMinimum
        needed += fit.layoutCells >= 3 ? threeCells : twoCells
        if fit.showsVersions { needed += versionsWidth }
        if fit.showsTransportToggle { needed += transportWidth }
        if fit.showsModeChip { needed += modeChipWidth }
        if fit.showsNumeral { needed += numeralWidth }
        return needed <= width
    }
}
