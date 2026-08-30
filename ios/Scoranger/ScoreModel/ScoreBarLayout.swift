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
///   3. layout control   three cells, then two
///   4. the title        flexible: it truncates, it does not disappear
///   5. version count    optional -- the title block opens the same band, so
///                       nothing becomes unreachable when it goes
///   6. the mode chip    optional, and the first to go -- the Edit button's
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
    static let modeChipWidth: CGFloat = 90
    /// Less than this and the title is not a title any more.
    static let titleMinimum: CGFloat = 100

    /// The bar's fixed furniture: the way out, three actions, and their gaps.
    static var essentials: CGFloat {
        padding + closeWidth + actionWidth * 3 + gap * 5
    }

    static func fit(barWidth: CGFloat) -> Fit {
        let everything = Fit(showsVersions: true, showsModeChip: true, layoutCells: 3)
        // Unmeasured: show everything rather than flashing a stripped bar on
        // the first frame and filling it in afterwards.
        guard barWidth > 0 else { return everything }

        let forAll = essentials + threeCells + versionsWidth + modeChipWidth + titleMinimum
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
        // Then the spread cell, which is the one a narrow screen cannot use.
        return Fit(showsVersions: false, showsModeChip: false, layoutCells: 2)
    }

    /// Whether a bar this wide can seat everything it is being asked to.
    /// Used by the test that guards the phone.
    static func fits(_ fit: Fit, in width: CGFloat) -> Bool {
        var needed = essentials + titleMinimum
        needed += fit.layoutCells >= 3 ? threeCells : twoCells
        if fit.showsVersions { needed += versionsWidth }
        if fit.showsModeChip { needed += modeChipWidth }
        return needed <= width
    }
}
