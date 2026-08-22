import CoreGraphics
import Foundation

/// Turns engraved whistle fingerings into drawn diagrams.
///
/// The fingerings are written into the notation as lyric verses, which is what
/// gets them positioned: Verovio reserves the space under the staff, stacks the
/// six holes in order and centres each column on its notehead. What Verovio
/// cannot do is draw a filled circle — it draws text, and the glyphs for ● and
/// ○ are missing from the fonts the PDF rasterizers fall back to, so they came
/// out as empty boxes. Hence letters in the notation and circles on the page:
/// this replaces each tagged verse glyph with an SVG shape at the coordinates
/// Verovio already chose.
///
/// Only verses tagged by the engine (`<title>wf</title>`, from
/// `<lyric name="wf">`) are touched, so a song whose lyric is the word "O" is
/// never turned into an open hole.
enum FingeringDiagrams {
    /// The engine's marker, mirrored from ops.WHISTLE_LYRIC_TAG.
    static let tag = "wf"

    static let covered = "X"
    static let open = "O"
    static let half = "/"

    // Proportions of the verse's own font size, so the diagram scales with the
    // engraving at any page size.
    private static let centreX: CGFloat = 0.36     // half a glyph advance
    private static let centreY: CGFloat = -0.35    // above the text baseline
    private static let radius: CGFloat = 0.28
    private static let strokeWidth: CGFloat = 0.07

    /// Rewrite every tagged verse in a Verovio SVG page.
    static func draw(in svg: String) -> String {
        guard svg.contains(">\(tag)<") else { return svg }   // nothing to do
        guard let verseRE = try? NSRegularExpression(
                pattern: "<g[^>]*class=\"verse\">.*?</g>\\s*</g>",
                options: [.dotMatchesLineSeparators]) else { return svg }

        let ns = svg as NSString
        var out = ""
        var cursor = 0
        for match in verseRE.matches(in: svg, range: NSRange(location: 0, length: ns.length)) {
            let block = ns.substring(with: match.range)
            out += ns.substring(with: NSRange(location: cursor,
                                              length: match.range.location - cursor))
            out += rewrite(block) ?? block
            cursor = match.range.location + match.range.length
        }
        out += ns.substring(from: cursor)
        return out
    }

    /// One verse group: a circle if it is a tagged hole, unchanged otherwise.
    private static func rewrite(_ block: String) -> String? {
        guard block.contains(">\(tag)</title>") else { return nil }
        guard let symbol = value(of: "(?<=>)[XO/](?=</tspan>)", in: block),
              [covered, open, half].contains(symbol),
              let x = number(of: "<text x=\"([-0-9.]+)\"", in: block),
              let y = number(of: "<text[^>]*y=\"([-0-9.]+)\"", in: block),
              // the INNER tspan carries the real size; the enclosing <text> is
              // font-size="0px", and reading that gave every circle a radius of
              // zero — invisible, while the host renderer (which reads the
              // tspan) drew them correctly
              let size = number(of: "<tspan font-size=\"([0-9.]+)px\">", in: block),
              size > 0
        else { return nil }

        let cx = x + centreX * size
        let cy = y + centreY * size
        let r = radius * size
        // Paths, not <circle>: SwiftDraw renders the subset Verovio emits, and
        // Verovio emits only paths and glyph <use>s — a <circle> came out of
        // the on-device renderer as nothing at all.
        let ring = Self.circlePath(cx: cx, cy: cy, r: r)
        let shape: String
        switch symbol {
        case covered:
            shape = "<path d=\"\(ring)\" fill=\"currentColor\" stroke=\"none\" />"
        case open:
            shape = "<path d=\"\(ring)\" fill=\"none\" stroke=\"currentColor\" "
                + "stroke-width=\"\(strokeWidth * size)\" />"
        default:
            // half-holed: an open ring with its lower half filled
            shape = "<path d=\"\(ring)\" fill=\"none\" stroke=\"currentColor\" "
                + "stroke-width=\"\(strokeWidth * size)\" />"
                + "<path d=\"M \(cx - r) \(cy) A \(r) \(r) 0 0 0 \(cx + r) \(cy) Z\" "
                + "fill=\"currentColor\" stroke=\"none\" />"
        }
        // keep the group (and its title) so nothing downstream loses its footing
        return replacingText(in: block, with: shape)
    }

    /// A full circle as two arcs, which every SVG renderer draws.
    static func circlePath(cx: CGFloat, cy: CGFloat, r: CGFloat) -> String {
        "M \(cx - r) \(cy) A \(r) \(r) 0 1 0 \(cx + r) \(cy) "
            + "A \(r) \(r) 0 1 0 \(cx - r) \(cy) Z"
    }

    /// Swap the `<text>…</text>` for the shape, leaving the rest of the group.
    private static func replacingText(in block: String, with shape: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: "<text.*?</text>",
                                                options: [.dotMatchesLineSeparators])
        else { return nil }
        let ns = block as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard re.firstMatch(in: block, range: range) != nil else { return nil }
        return re.stringByReplacingMatches(in: block, range: range,
                                           withTemplate: shape)
    }

    private static func value(of pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text,
                                    range: NSRange(location: 0, length: (text as NSString).length))
        else { return nil }
        return (text as NSString).substring(with: m.range)
    }

    private static func number(of pattern: String, in text: String) -> CGFloat? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text,
                                    range: NSRange(location: 0, length: (text as NSString).length)),
              m.numberOfRanges > 1
        else { return nil }
        return CGFloat(Double((text as NSString).substring(with: m.range(at: 1))) ?? 0)
    }
}
