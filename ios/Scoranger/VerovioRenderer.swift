import Foundation
import PDFKit
import SwiftDraw
import VerovioToolkit

/// On-device engraving: MusicXML -> SVG pages (Verovio) -> PDF (SwiftDraw).
/// The toolkit is not thread-safe, so everything runs inside this actor.
actor VerovioRenderer {
    static let shared = VerovioRenderer()

    private var toolkit: VerovioToolkit?

    enum RenderError: Error, LocalizedError {
        case resourcesMissing
        case loadFailed(String)
        case emptyPage(Int)
        var errorDescription: String? {
            switch self {
            case .resourcesMissing: return "Verovio resources bundle missing"
            case .loadFailed(let p): return "Verovio could not load \(p)"
            case .emptyPage(let n): return "Verovio rendered an empty page \(n)"
            }
        }
    }

    private func tk() throws -> VerovioToolkit {
        if let toolkit { return toolkit }
        let t = VerovioToolkit()
        guard let dataPath = VerovioResources.bundle.path(forResource: "data", ofType: nil),
              t.setResourcePath(dataPath) else {
            throw RenderError.resourcesMissing
        }
        // A4 portrait-ish pages at a comfortable reading scale
        _ = t.setOptions("""
            {"scale": 45, "footer": "none",
             "pageMarginTop": 100, "pageMarginBottom": 100,
             "pageMarginLeft": 120, "pageMarginRight": 120}
            """)
        toolkit = t
        return t
    }

    /// Render a MusicXML file to a multi-page PDF document.
    func renderPDF(musicXMLPath: String) throws -> Data {
        let t = try tk()
        guard t.loadFile(musicXMLPath) else {
            throw RenderError.loadFailed(musicXMLPath)
        }
        let document = PDFDocument()
        for page in 1...max(t.getPageCount(), 1) {
            let svg = t.renderToSVG(page, true)
            let prepared = Self.prepareForSwiftDraw(svg)
            guard !prepared.isEmpty, let parsed = SVG(data: Data(prepared.utf8)) else {
                throw RenderError.emptyPage(page)
            }
            let pageData = try parsed.pdfData()
            if let pageDoc = PDFDocument(data: pageData), let p = pageDoc.page(at: 0) {
                document.insert(p, at: document.pageCount)
            }
        }
        guard let data = document.dataRepresentation() else {
            throw RenderError.emptyPage(0)
        }
        return data
    }

    // MARK: SVG preprocessing
    //
    // SwiftDraw doesn't process Verovio's CSS (`path {stroke:currentColor}`),
    // nested <svg viewBox> scaling, or double-nested <tspan> text — so we
    // rewrite the SVG into the plain subset it does handle. Validated against
    // the desktop toolchain (same output as the browser render).

    private static let accidentalSubs: [(String, String)] = [
        ("\u{E260}", "b"), ("\u{E262}", "#"), ("\u{E261}", ""),
        ("\u{EA64}", "b"), ("\u{EA66}", "#"), ("\u{EA65}", ""),
        ("\u{266D}", "b"), ("\u{266F}", "#"), ("\u{266E}", ""),
    ]

    static func prepareForSwiftDraw(_ svg: String) -> String {
        var s = svg
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
    private static func flattenTextElements(_ svg: String) -> String {
        guard let blockRe = try? NSRegularExpression(
            pattern: "<text[^>]*>.*?</text>", options: [.dotMatchesLineSeparators]),
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
