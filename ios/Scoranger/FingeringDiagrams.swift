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
/// Two kinds of verse are converted. Ones the engine tagged (`<title>wf</title>`,
/// from `<lyric name="wf">`), and ones that are unmistakably a fingering column
/// even without the tag: five or six verses on the same note, every one of them
/// a single X, O or /. The second rule exists because fingerings written before
/// the tag existed are sitting in people's scores, and a renderer that only
/// understood its own new output would leave those as letters forever.
///
/// A song whose lyric happens to be the word "O" is safe either way: one verse
/// is not a column.
enum FingeringDiagrams {
    /// The engine's marker, mirrored from ops.WHISTLE_LYRIC_TAG.
    static let tag = "wf"

    static let covered = "X"
    static let open = "O"
    static let half = "/"
    /// The overblown-octave mark. It stays text — it is a "+", which every font
    /// has — but it belongs to the column, so a run containing it is still a
    /// fingering. Requiring every verse to be a hole rejected the whole second
    /// octave.
    static let octave = "+"

    // Proportions of the verse's own font size, so the diagram scales with the
    // engraving at any page size.
    private static let centreX: CGFloat = 0.36     // half a glyph advance
    private static let centreY: CGFloat = -0.35    // above the text baseline
    private static let radius: CGFloat = 0.28
    private static let strokeWidth: CGFloat = 0.07

    /// The engraving's one text size, in MEI units. It stays at Verovio's
    /// default because `lyricSize` also sizes `<harm>` chord symbols: shrinking
    /// it to shrink the diagrams halved every chord name on a fingered score.
    static let defaultLyricSize = 4.5
    /// How much smaller the drawn diagram is than the glyph it replaces -- the
    /// same 2.2-in-4.5 the diagrams shipped at, applied here instead.
    static let diagramScale: CGFloat = 2.2 / 4.5

    /// Smallest run of same-note verses that reads as a fingering rather than
    /// as words. Six holes is a full diagram; five allows for an engraver
    /// dropping an empty verse.
    static let columnThreshold = 5

    /// One verse, parsed far enough to decide what it is.
    private struct Verse {
        let range: NSRange
        let block: String
        let tagged: Bool
        let symbol: String?
        /// Whatever the verse actually says, hole or not.
        let text: String?
        /// The verse's own number, which restarts at 1 on each note. Grouping
        /// on this rather than on x: Verovio centres each syllable on its own
        /// width, so an "X" verse and an "O" verse of the SAME note sit at
        /// different x, and a column of mixed holes never grouped.
        let number: Int?
    }

    /// Mark fingering verses `place="above"` in MEI, or nil when there are none.
    ///
    /// Verovio ignores MusicXML's `<lyric placement="above">`, but honours MEI's
    /// `place` on `<verse>` — so the move happens on an MEI round trip rather
    /// than in the notation. The same column rule as the SVG pass decides what
    /// counts, which is what carries fingerings written before the tag existed.
    static func meiWithFingeringsAbove(_ mei: String) -> String? {
        guard mei.contains("<verse") else { return nil }
        // chord first: a fingered note inside a chord hangs its verses off the
        // chord, and matching the inner <note> separately would miss them
        guard let noteRE = try? NSRegularExpression(
                pattern: "<(chord|note)\\b[^>]*>.*?</\\1>",
                options: [.dotMatchesLineSeparators]),
              let verseRE = try? NSRegularExpression(
                pattern: "<verse\\b[^>]*>.*?</verse>",
                options: [.dotMatchesLineSeparators])
        else { return nil }

        let ns = mei as NSString
        var out = ""
        var cursor = 0
        var changed = false
        for match in noteRE.matches(in: mei, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: cursor,
                                              length: match.range.location - cursor))
            let block = ns.substring(with: match.range)
            let blockNS = block as NSString
            let verses = verseRE.matches(
                in: block, range: NSRange(location: 0, length: blockNS.length))
                .map { blockNS.substring(with: $0.range) }
            if verses.count >= columnThreshold, isFingeringColumn(verses) {
                changed = true
                out += verseRE.stringByReplacingMatches(
                    in: block, range: NSRange(location: 0, length: blockNS.length),
                    withTemplate: "$0").replacingOccurrences(
                        of: "<verse ", with: "<verse place=\"above\" ")
            } else {
                out += block
            }
            cursor = match.range.location + match.range.length
        }
        out += ns.substring(from: cursor)
        return changed ? out : nil
    }

    /// Five or six single holes on one note, with the octave "+" allowed.
    private static func isFingeringColumn(_ verses: [String]) -> Bool {
        var holes = 0
        for verse in verses {
            guard let syl = value(of: "(?<=<syl[^<>]{0,200}>)[^<]*(?=</syl>)", in: verse)
                    ?? value(of: "(?<=<syl>)[^<]*(?=</syl>)", in: verse) else { return false }
            let text = syl.trimmingCharacters(in: .whitespacesAndNewlines)
            if [covered, open, half].contains(text) { holes += 1 }
            else if text != octave { return false }
        }
        return holes >= columnThreshold
    }

    /// Rewrite every fingering verse in a Verovio SVG page.
    static func draw(in svg: String) -> String {
        guard svg.contains("class=\"verse\"") else { return svg }
        guard let verseRE = try? NSRegularExpression(
                pattern: "<g[^>]*class=\"verse\">.*?</g>\\s*</g>",
                options: [.dotMatchesLineSeparators]) else { return svg }

        let ns = svg as NSString
        let verses = verseRE.matches(in: svg, range: NSRange(location: 0, length: ns.length))
            .map { match -> Verse in
                let block = ns.substring(with: match.range)
                let label = value(of: "(?<=<title class=\"labelAttr\">)[^<]*(?=</title>)",
                                  in: block)
                return Verse(range: match.range,
                             block: block,
                             tagged: label == tag,
                             symbol: fingeringSymbol(in: block),
                             text: value(of: "(?<=>)[^<>]{1,3}(?=</tspan>)", in: block),
                             number: label.flatMap { Int($0) })
            }
        guard !verses.isEmpty else { return svg }

        let convertible = columns(in: verses)
        guard convertible.contains(true) else { return svg }

        var out = ""
        var cursor = 0
        for (index, verse) in verses.enumerated() {
            out += ns.substring(with: NSRange(location: cursor,
                                              length: verse.range.location - cursor))
            if convertible[index], let drawn = rewrite(verse.block) {
                out += drawn
            } else if verse.tagged, verse.text == octave {
                // it belongs to the column, so it shrinks with it -- left at
                // full text size it stands twice as tall as its own holes
                out += scaleText(verse.block) ?? verse.block
            } else {
                out += verse.block
            }
            cursor = verse.range.location + verse.range.length
        }
        out += ns.substring(from: cursor)
        return out
    }

    /// Which verses belong to a fingering: tagged ones, and untagged ones that
    /// sit in a tall column of holes on a single note.
    private static func columns(in verses: [Verse]) -> [Bool] {
        var convert = verses.map { $0.tagged && $0.symbol != nil }
        var runStart = 0
        while runStart < verses.count {
            var runEnd = runStart
            // one note's verses are numbered 1, 2, 3…; the next note starts
            // over, which is where one column ends and the next begins
            while runEnd + 1 < verses.count,
                  let here = verses[runEnd].number,
                  let next = verses[runEnd + 1].number,
                  next > here {
                runEnd += 1
            }
            let run = verses[runStart...runEnd]
            let holes = run.filter { $0.symbol != nil }.count
            let onlyHolesAndOctave = run.allSatisfy {
                $0.symbol != nil || $0.text == octave
            }
            if holes >= columnThreshold, onlyHolesAndOctave {
                for i in runStart...runEnd where verses[i].symbol != nil {
                    convert[i] = true
                }
            }
            runStart = runEnd + 1
        }
        return convert
    }

    /// The hole this verse draws, if it is one.
    private static func fingeringSymbol(in block: String) -> String? {
        guard let symbol = value(of: "(?<=>)[XO/](?=</tspan>)", in: block),
              [covered, open, half].contains(symbol) else { return nil }
        return symbol
    }

    /// One verse group, already judged to be a hole: draw it.
    private static func rewrite(_ block: String) -> String? {
        guard let symbol = fingeringSymbol(in: block),
              let x = number(of: "<text x=\"([-0-9.]+)\"", in: block),
              let y = number(of: "<text[^>]*y=\"([-0-9.]+)\"", in: block),
              // the INNER tspan carries the real size; the enclosing <text> is
              // font-size="0px", and reading that gave every circle a radius of
              // zero — invisible, while the host renderer (which reads the
              // tspan) drew them correctly
              let size = number(of: "<tspan font-size=\"([0-9.]+)px\">", in: block),
              size > 0
        else { return nil }

        // the glyph is full size now; the diagram drawn in its place is not
        let drawn = size * diagramScale
        let cx = x + centreX * drawn
        let cy = y + centreY * drawn
        let r = radius * drawn
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
                + "stroke-width=\"\(strokeWidth * drawn)\" />"
        default:
            // half-holed: an open ring with its lower half filled
            shape = "<path d=\"\(ring)\" fill=\"none\" stroke=\"currentColor\" "
                + "stroke-width=\"\(strokeWidth * drawn)\" />"
                + "<path d=\"M \(cx - r) \(cy) A \(r) \(r) 0 0 0 \(cx + r) \(cy) Z\" "
                + "fill=\"currentColor\" stroke=\"none\" />"
        }
        // keep the group (and its title) so nothing downstream loses its footing
        return replacingText(in: block, with: shape)
    }

    /// Shrink a verse's glyph to the diagram scale, leaving it as text.
    private static func scaleText(_ block: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: "<tspan font-size=\"([0-9.]+)px\">"),
              let m = re.firstMatch(in: block,
                                    range: NSRange(location: 0, length: (block as NSString).length)),
              m.numberOfRanges > 1
        else { return nil }
        let ns = block as NSString
        let size = CGFloat(Double(ns.substring(with: m.range(at: 1))) ?? 0)
        guard size > 0 else { return nil }
        return ns.replacingCharacters(
            in: m.range, with: "<tspan font-size=\"\(size * diagramScale)px\">")
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
