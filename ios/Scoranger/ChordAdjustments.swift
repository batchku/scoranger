import CoreGraphics
import Foundation

/// Carries a chord symbol's size and position from the notation onto the page.
///
/// The user's adjustment lives in the MusicXML — `font-size`, `relative-x` and
/// `relative-y` on `<harmony>` — because that is standard, portable, and
/// travels with the score. What it does not do is reach Verovio: its MusicXML
/// importer drops all three, measured, so they have to be carried across here.
///
/// Position becomes MEI `@ho`/`@vo`, which Verovio honours per element. Size is
/// applied to the rendered SVG afterwards, because Verovio has no per-element
/// text size at all — `@fontsize` is ignored as a percentage and as a keyword.
///
/// Mirrors engine/scoranger_engine/render.py; keep the two in step.
enum ChordAdjustments {
    /// One chord symbol's adjustment, or nothing where the user left it alone.
    struct Adjustment: Equatable {
        var size: CGFloat?
        var dx: CGFloat?
        var dy: CGFloat?

        var isEmpty: Bool { size == nil && dx == nil && dy == nil }
    }

    /// The point size a chord symbol engraves at untouched, so a stored
    /// absolute size can be expressed as a ratio of the drawn glyph.
    static let defaultChordPoints: CGFloat = 12
    /// MEI counts half-spaces; MusicXML counts tenths of a staff space.
    static let tenthsToHalfSpaces: CGFloat = 0.2

    /// Every chord symbol's adjustment, in document order — the same order the
    /// MEI and the SVG present them in, which is what lets them be matched up
    /// without inventing an identity scheme.
    static func adjustments(inMusicXML xml: String) -> [Adjustment] {
        guard let tagRE = try? NSRegularExpression(pattern: "<harmony\\b[^>]*>") else { return [] }
        let ns = xml as NSString
        return tagRE.matches(in: xml, range: NSRange(location: 0, length: ns.length))
            .map { match in
                let tag = ns.substring(with: match.range)
                return Adjustment(size: number("font-size", in: tag),
                                  dx: number("relative-x", in: tag),
                                  dy: number("relative-y", in: tag))
            }
    }

    /// Put each symbol's offset into the MEI, or nil when none has one.
    static func meiWithAdjustments(_ mei: String, adjustments: [Adjustment]) -> String? {
        guard adjustments.contains(where: { $0.dx != nil || $0.dy != nil }),
              let harmRE = try? NSRegularExpression(pattern: "<harm\\b") else { return nil }

        let ns = mei as NSString
        var out = ""
        var cursor = 0
        var index = 0
        for match in harmRE.matches(in: mei, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: cursor,
                                              length: match.range.location - cursor))
            out += ns.substring(with: match.range)
            if index < adjustments.count {
                let adjustment = adjustments[index]
                if let dx = adjustment.dx {
                    out += " ho=\"\(dx * tenthsToHalfSpaces)\""
                }
                if let dy = adjustment.dy {
                    // MusicXML measures up, MEI's @vo measures down
                    out += " vo=\"\(-dy * tenthsToHalfSpaces)\""
                }
            }
            index += 1
            cursor = match.range.location + match.range.length
        }
        out += ns.substring(from: cursor)
        return out
    }

    /// Rescale each adjusted symbol's glyph in the rendered SVG.
    ///
    /// The size lives on the INNER tspan, and that tspan carries x and y AFTER
    /// its font-size — the enclosing `<text>` is `font-size="0px"`. Reading the
    /// wrong one is what once drew every fingering circle with a radius of zero.
    static func applySizes(_ svg: String, adjustments: [Adjustment]) -> String {
        guard adjustments.contains(where: { $0.size != nil }),
              let blockRE = try? NSRegularExpression(
                pattern: "<g[^>]*class=\"harm\".*?</g>\\s*</g>",
                options: [.dotMatchesLineSeparators]),
              let sizeRE = try? NSRegularExpression(
                pattern: "(<tspan[^>]*font-size=\")([0-9.]+)(px\")")
        else { return svg }

        let ns = svg as NSString
        var out = ""
        var cursor = 0
        var index = 0
        for match in blockRE.matches(in: svg, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: cursor,
                                              length: match.range.location - cursor))
            var block = ns.substring(with: match.range)
            if index < adjustments.count, let wanted = adjustments[index].size {
                let blockNS = block as NSString
                if let hit = sizeRE.firstMatch(
                    in: block, range: NSRange(location: 0, length: blockNS.length)),
                   hit.numberOfRanges > 3,
                   let drawn = Double(blockNS.substring(with: hit.range(at: 2))), drawn > 0 {
                    let scale = wanted / defaultChordPoints
                    let replacement = blockNS.substring(with: hit.range(at: 1))
                        + "\(CGFloat(drawn) * scale)"
                        + blockNS.substring(with: hit.range(at: 3))
                    block = blockNS.replacingCharacters(in: hit.range, with: replacement)
                }
            }
            out += block
            index += 1
            cursor = match.range.location + match.range.length
        }
        out += ns.substring(from: cursor)
        return out
    }

    private static func number(_ attribute: String, in tag: String) -> CGFloat? {
        guard let re = try? NSRegularExpression(pattern: "\(attribute)=\"([-0-9.]+)\""),
              let m = re.firstMatch(in: tag,
                                    range: NSRange(location: 0, length: (tag as NSString).length)),
              m.numberOfRanges > 1,
              let value = Double((tag as NSString).substring(with: m.range(at: 1)))
        else { return nil }
        return CGFloat(value)
    }
}
