import Foundation

/// Verovio's SVG, rewritten into the subset SwiftDraw can actually draw.
///
/// This is regex surgery on generated markup, and it lived inside the renderer
/// where no test could reach it — which is how a score that Verovio drew
/// perfectly could fail to reach the page with the renderer reporting "Verovio
/// rendered an empty page". It is pure string work, so it belongs here in the
/// host-less bundle where its behaviour can be pinned to real engravings.
///
/// Three things happen, and each is a place this can go wrong:
///
/// 1. fingerings become drawn circles and chord diagrams drawn grids, and
    ///    SMuFL accidentals become ASCII —
///    the rasteriser's fallback font has neither
/// 2. the inner `<svg class="definition-scale">` is flattened into a `<g>`,
///    hoisting its viewBox onto the root, which has only px width/height
/// 3. nested `<tspan>` runs are flattened into positioned `<text>` elements
enum SVGForSwiftDraw {
    static let accidentalSubs: [(String, String)] = [
        ("\u{E260}", "b"), ("\u{E262}", "#"), ("\u{E261}", ""),
        ("\u{EA64}", "b"), ("\u{EA66}", "#"), ("\u{EA65}", ""),
        ("\u{266D}", "b"), ("\u{266F}", "#"), ("\u{266E}", ""),
    ]

    static func prepare(_ svg: String) -> String {
        // fingerings become drawn circles before anything else looks at the
        // text: they are shapes from here on, not glyphs
        var s = TabStaff.draw(in: ChordDiagrams.draw(in: FingeringDiagrams.draw(in: svg)))
        for (glyph, ascii) in accidentalSubs {
            s = s.replacingOccurrences(of: glyph, with: ascii)
        }
        s = s.replacingOccurrences(of: "currentColor", with: "black")

        // flatten <svg class="definition-scale" viewBox="..."> into a <g>,
        // hoisting its viewBox onto the root svg (which has only px width/height)
        if let inner = s.range(of: #"<svg class="definition-scale"[^>]*>"#,
                               options: .regularExpression) {
            let tag = String(s[inner])
            var viewBox = ""
            if let vb = tag.range(of: #"viewBox="[^"]*""#, options: .regularExpression) {
                viewBox = String(tag[vb])
            }
            s.replaceSubrange(inner, with: #"<g stroke="black" color="black">"#)
            if let close = s.range(of: "</svg>") {
                s.replaceSubrange(close, with: "</g>")
            }
            if !viewBox.isEmpty, let root = s.range(of: "<svg ") {
                s.replaceSubrange(root, with: "<svg \(viewBox) ")
            }
        }

        return flattenTextElements(s)
    }

    /// Rewrite every <text> block (arbitrarily nested tspans) into flat
    /// <text> elements: one per positioned tspan, style attrs inherited from
    /// the tspan stack, unpositioned runs (chord accidentals) appended to the
    /// preceding positioned run.
    ///
    /// Verovio positions text two ways. Chord symbols repeat x/y on the inner
    /// tspan; staff labels, tuplet numbers and page numbers carry x/y on the
    /// enclosing <text> and leave every tspan unpositioned. Grouping only on a
    /// positioned tspan therefore discarded the whole second category -- which
    /// is why instrument names never reached the page. So a block opens with a
    /// group seeded from the <text> element itself, and a positioned tspan
    /// still starts a fresh one.
    ///
    /// Only x/y/text-anchor come from <text>: it also carries font-size="0px"
    /// (the real size lives on the inner tspan), and seeding that would emit
    /// correctly placed but invisible zero-height text.
    static func flattenTextElements(_ svg: String) -> String {
        // TEMPERED: the span may not cross another <text opening.
        //
        // `<text[^>]*>.*?</text>` looks safe because it is non-greedy, but it
        // is only safe while every <text is closed. An UNCLOSED or self-closing
        // one -- OMR output has them -- makes the match start there and run to
        // the NEXT block's </text>, swallowing every <g>, <use> and <path>
        // between the two. Those elements are then dropped by the rewrite: on
        // the score that exposed this, 77 <use>, 127 <path> and 282 <g>
        // vanished, 43KB of drawing, and what was left would not parse. The
        // renderer reported it as "Verovio rendered an empty page", which is
        // how it stayed hidden -- the page was fine until we rewrote it.
        //
        // `(?:(?!<text[^>]*>).)*?` is the same non-greedy body that additionally
        // refuses to step over another opening tag.
        guard let blockRe = try? NSRegularExpression(
            pattern: "<text[^>]*[^/]>(?:(?!<text[^>]*>).)*?</text>",
            options: [.dotMatchesLineSeparators]),
            let tokenRe = try? NSRegularExpression(pattern: "<[^>]+>|[^<]+"),
            let attrRe = try? NSRegularExpression(pattern: #"([a-zA-Z-]+)="([^"]*)""#),
            let titleRe = try? NSRegularExpression(
                pattern: "<title[^>]*>.*?</title>", options: [.dotMatchesLineSeparators])
        else { return svg }

        let ns = svg as NSString
        var result = ""
        var cursor = 0
        for match in blockRe.matches(in: svg, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor,
                                                 length: match.range.location - cursor))
            var block = ns.substring(with: match.range)
            block = titleRe.stringByReplacingMatches(
                in: block, range: NSRange(location: 0, length: (block as NSString).length),
                withTemplate: "")

            var stack: [[String: String]] = []
            var out = ""
            var groupAttrs: [String: String]? = nil
            var groupText = ""
            func closeGroup() {
                if let attrs = groupAttrs,
                   !groupText.trimmingCharacters(in: .whitespaces).isEmpty {
                    let rendered = attrs.map { " \($0.key)=\"\($0.value)\"" }.sorted().joined()
                    out += "<text\(rendered)>\(groupText)</text>"
                }
                groupAttrs = nil
                groupText = ""
            }
            func attrs(of tag: String) -> [String: String] {
                var d: [String: String] = [:]
                let t = tag as NSString
                for m in attrRe.matches(in: tag, range: NSRange(location: 0, length: t.length)) {
                    d[t.substring(with: m.range(at: 1))] = t.substring(with: m.range(at: 2))
                }
                return d
            }

            let blockNS = block as NSString

            // seed from the <text> open tag, so text that never meets a
            // positioned tspan still has somewhere to land
            if let openTag = block.range(of: "<text[^>]*>", options: .regularExpression) {
                let a = attrs(of: String(block[openTag]))
                if a["x"] != nil {
                    var g: [String: String] = [:]
                    for key in ["x", "y", "text-anchor"] { g[key] = a[key] }
                    groupAttrs = g.compactMapValues { $0 }
                }
            }

            for tok in tokenRe.matches(in: block,
                                       range: NSRange(location: 0, length: blockNS.length)) {
                let token = blockNS.substring(with: tok.range)
                if token.hasPrefix("<tspan") {
                    let a = attrs(of: token)
                    stack.append(a)
                    if a["x"] != nil {
                        closeGroup()
                        var g: [String: String] = [:]
                        for key in ["x", "y", "text-anchor"] { g[key] = a[key] }
                        groupAttrs = g.compactMapValues { $0 }
                    }
                } else if token.hasPrefix("</tspan") {
                    if !stack.isEmpty { stack.removeLast() }
                } else if !token.hasPrefix("<") {
                    let text = token.replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespaces)
                    if !text.isEmpty, groupAttrs != nil {
                        for key in ["font-size", "font-family", "font-weight", "font-style"] {
                            guard groupAttrs?[key] == nil else { continue }
                            for level in stack.reversed() {
                                if let v = level[key],
                                   !(key == "font-size" && (v == "0px" || v == "0")) {
                                    groupAttrs?[key] = v
                                    break
                                }
                            }
                        }
                        groupText += text
                    }
                }
            }
            closeGroup()
            result += out
            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }
}
