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

    static let rowHeight: CGFloat = 33
    static let headerHeight: CGFloat = 24

    /// Never more than this much of the score. Past it the band scrolls
    /// internally: the music stays readable behind the thing you opened to
    /// change it.
    static let maxFraction: CGFloat = 0.4

    /// The band's natural height: the taller of its two columns.
    static func contentHeight(arrangements: Int, versions: Int,
                              hasAllVersionsRow: Bool) -> CGFloat {
        let left = headerHeight + CGFloat(max(arrangements, 1)) * rowHeight
        let right = headerHeight
            + CGFloat(max(versions, 1) + (hasAllVersionsRow ? 1 : 0)) * rowHeight
        return max(left, right)
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
    static func versionLabel(prompt: String?, op: String) -> String {
        let cleaned = (prompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty { return cleaned }
        return op.isEmpty ? "—" : op
    }
}
