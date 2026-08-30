import Foundation

/// What a change of engraving means, and therefore what may be thrown away.
///
/// Every render is keyed `slug/version/layout`. When that key changes the canvas used
/// to be blanked and the selection cleared, whatever the change was -- and a
/// prompt transform changes it, because an op makes a new version. So running
/// "transpose these bars up a tone" on a selection blanked the whole score,
/// re-engraved it, and lost the selection: two of the three things Ali
/// complained about, from one branch that could not tell a NEW SCORE from the
/// SAME score one op later (#44).
///
/// They are not the same event:
///
///   - a different score is a different subject. The old page must go at once,
///     because leaving it up would show one arrangement while claiming to have
///     opened another -- which is the bug the blanking was added to fix.
///   - the same score, one version on, is the SAME MUSIC. Its previous
///     engraving is the best thing to show until the next one is ready, and
///     everything the reader had selected is still addressable in it.
enum RenderTransition: Equatable {
    /// Nothing was on screen: the first engrave of a session.
    case first
    /// The same arrangement, a different version -- an op, or a version pick.
    case sameScore
    /// A different arrangement entirely.
    case differentScore

    /// Keys are `slug/version/layout`; the slug is what decides. Switching to
    /// the continuous layout re-engraves the same music, so it reads as the
    /// same score and the pages on screen stay up until the new ones arrive.
    static func between(previous: String?, next: String) -> RenderTransition {
        guard let previous, !previous.isEmpty else { return .first }
        if previous == next { return .sameScore }
        return slug(of: previous) == slug(of: next) ? .sameScore : .differentScore
    }

    private static func slug(of key: String) -> Substring {
        key.split(separator: "/").first ?? ""
    }

    /// Whether the page on screen must be taken down before the new one is
    /// ready. Only when the subject changed: a blank canvas is honest about a
    /// score you have not opened yet, and dishonest about one you are editing.
    var blanksTheCanvas: Bool { self == .differentScore }

    /// Whether the reader's place in the score survives -- which page they are
    /// on, and what they had selected. An op does not move them.
    var keepsPlace: Bool { self != .differentScore }
}
