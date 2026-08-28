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
        _ = t.setOptions(Self.options(lyricSize: FingeringDiagrams.defaultLyricSize))
        toolkit = t
        return t
    }

    /// A page is a FIXED size: US Letter portrait, which is what the sources
    /// are (the sample PDFs measure 8.5x11 and 8.26x11.69, both portrait).
    ///
    /// This replaces `adjustPageHeight`, which trimmed each page to its own
    /// content. That went in at build 119 for a real reason -- without it a
    /// partly filled last page rendered as a tall white void. But trimming
    /// means a page holding less music is a SHORTER page, which is what Ali's
    /// two-page spread showed: the left page's bottom edge above the right's.
    /// Paper does not do that. White at the bottom of a partial page is
    /// correct; pages of different heights never are.
    ///
    /// Verovio lays out in TENTHS OF A MILLIMETRE -- its own A4 default,
    /// 2100 x 2970, is 210 x 297mm -- so US Letter is 2159 x 2794. Mirrors
    /// render.py's PAGE_WIDTH_TENTHS_MM / PAGE_HEIGHT_TENTHS_MM; keep the two
    /// in step.
    ///
    /// These were 816 x 1056 for one build, from measuring an exported PDF and
    /// reading 96 units to the inch off it. That is the arithmetic for the
    /// PDF's physical size, which is applied separately, and it told Verovio
    /// the paper was 82 x 106mm. The engraving was laid out for a postcard:
    /// this quartet paginated to 131 pages of enormous notes.
    static let pageWidthTenthsMM = 2159
    static let pageHeightTenthsMM = 2794

    /// The full option set every time: passing a partial one risks the rest
    /// reverting to Verovio's defaults, which would quietly bring back the
    /// trimmed, uneven pages.
    private static func options(lyricSize: Double) -> String {
        """
        {"scale": 45, "footer": "none", "adjustPageHeight": false,
         "pageWidth": \(pageWidthTenthsMM), "pageHeight": \(pageHeightTenthsMM),
         "pageMarginTop": 100, "pageMarginBottom": 100,
         "pageMarginLeft": 120, "pageMarginRight": 120,
         "lyricSize": \(lyricSize)}
        """
    }

    /// One engrave: the pages to draw, and the model to hit-test against.
    ///
    /// Both come from the same Verovio load, which is the whole point — a
    /// selection is only meaningful if the geometry it queries is the geometry
    /// on screen. The PDF is built from the SwiftDraw-flattened SVG; the model
    /// is built from Verovio's own SVG, which still has the class/id structure
    /// the parser needs.
    struct Engraving {
        let pdf: Data
        /// nil when the model could not be built. The page still draws: a
        /// selection that cannot be made is better than a score that cannot be
        /// read.
        let geometry: ScoreGeometry?
        /// What each chord symbol already carries, by address, so the chip
        /// starts a nudge from the truth in the file rather than from the
        /// default. Matched by document order -- the same 1:1 correspondence
        /// between <harmony> tags and <harm> elements that ChordAdjustments
        /// relies on to place the offsets in the first place.
        var chordAdjustments: [ScoreAddress: ChordAdjustments.Adjustment] = [:]
    }

    func engrave(musicXMLPath: String) throws -> Engraving {
        let t = try tk()
        guard t.loadFile(musicXMLPath) else {
            throw RenderError.loadFailed(musicXMLPath)
        }
        // Whistle fingerings belong above their staff. Verovio ignores
        // MusicXML's lyric placement, so the move is made on the MEI and the
        // document reloaded before anything is drawn.
        var mei = t.getMEI("{}")
        // One text size, whatever the score carries: `lyricSize` also sizes
        // chord symbols, so shrinking it for the diagrams halved every chord
        // name on a fingered score. The diagrams are scaled in our own pass.
        _ = t.setOptions(Self.options(lyricSize: FingeringDiagrams.defaultLyricSize))

        // The user's chord-symbol adjustments live in the MusicXML, and
        // Verovio's importer drops them, so they are carried across here.
        let source = (try? String(contentsOfFile: musicXMLPath, encoding: .utf8)) ?? ""
        let adjustments = ChordAdjustments.adjustments(inMusicXML: source)

        var reload = false
        if let above = FingeringDiagrams.meiWithFingeringsAbove(mei) {
            mei = above
            reload = true
        }
        // Real Book placement, for the symbols whose notation asks for it. The
        // PDF renderer used to apply this to EVERY score with a chord symbol
        // and this one to none, so the same file drew its names on the staff in
        // an export and above it here -- and a nudge would have meant two
        // different things. Both read the notation now.
        if let styled = ChordPlacement.meiWithChartStyling(
            mei, onStaff: ChordPlacement.onStaffFlags(inMusicXML: source)) {
            mei = styled
            reload = true
        }
        if let placed = ChordAdjustments.meiWithAdjustments(mei, adjustments: adjustments) {
            mei = placed
            reload = true
        }
        if reload {
            guard t.loadData(mei) else { throw RenderError.loadFailed(musicXMLPath) }
        }
        let document = PDFDocument()
        var rawPages: [String] = []
        for page in 1...max(t.getPageCount(), 1) {
            // size is applied to the drawn glyph, because Verovio has no
            // per-element text size to ask for
            let svg = ChordAdjustments.applySizes(t.renderToSVG(page, true),
                                                  adjustments: adjustments)
            rawPages.append(svg)
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
        // the same MEI the pages were drawn from, so addresses line up
        let geometry = try? ScoreModelBuilder.build(svgPages: rawPages, mei: mei)
        return Engraving(pdf: data, geometry: geometry,
                         chordAdjustments: Self.byAddress(adjustments, in: geometry))
    }

    /// Pair each chord symbol's stored adjustment with its address.
    ///
    /// Both sequences are in document order -- the geometry's harm elements
    /// come from the same MEI the offsets were written into -- so they zip.
    /// A mismatch in count means the join is unsafe, and nothing is returned
    /// rather than a map that is subtly wrong about which symbol is which.
    static func byAddress(_ adjustments: [ChordAdjustments.Adjustment],
                          in geometry: ScoreGeometry?)
        -> [ScoreAddress: ChordAdjustments.Adjustment] {
        guard let geometry, !adjustments.isEmpty else { return [:] }
        let harms = geometry.pages
            .flatMap(\.elements)
            .compactMap(\.address)
            .filter { $0.kind == .harm }
        guard harms.count == adjustments.count else { return [:] }
        return Dictionary(uniqueKeysWithValues: zip(harms, adjustments))
    }

    /// Pages only, for callers with nothing to select (export, iPhone).
    func renderPDF(musicXMLPath: String) throws -> Data {
        try engrave(musicXMLPath: musicXMLPath).pdf
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
        // fingerings become drawn circles before anything else looks at the
        // text: they are shapes from here on, not glyphs
        var s = FingeringDiagrams.draw(in: svg)
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
