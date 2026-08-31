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
        /// Verovio itself produced nothing for this page.
        case pageEmpty(Int)
        /// Verovio drew the page and OUR rewrite of it would not parse. A
        /// different failure with a different fix, and it used to report
        /// itself as `emptyPage` -- which sent three people hunting degenerate
        /// notation for a score that was fine (see SVGForSwiftDraw).
        case pageUnconvertible(Int)
        /// Not one page of the score could be drawn.
        case nothingDrawn
        var errorDescription: String? {
            switch self {
            case .resourcesMissing: return "Verovio resources bundle missing"
            case .loadFailed(let p): return "Verovio could not load \(p)"
            case .pageEmpty(let n): return "Verovio drew nothing for page \(n)"
            case .pageUnconvertible(let n):
                return "Page \(n) was engraved but could not be converted for display"
            case .nothingDrawn: return "No page of this version could be drawn"
            }
        }

        var pageNumber: Int? {
            switch self {
            case .pageEmpty(let n), .pageUnconvertible(let n): return n
            case .resourcesMissing, .loadFailed, .nothingDrawn: return nil
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
    private static func options(lyricSize: Double, continuous: Bool = false) -> String {
        // `breaks: none` puts every system on one line. Verovio then sizes the
        // page to the content itself -- an eleven-page score comes back as one
        // page about 21000px wide -- so `pageWidth` is not a ceiling to raise
        // here; it is ignored. `adjustPageHeight` trims the height to the one
        // system, which is what makes the surface a strip rather than a sheet.
        let breaks = continuous ? #""breaks": "none", "adjustPageHeight": true,"#
                                : #""adjustPageHeight": false,"#
        // A page's top and bottom margins are paper: they keep a printed page
        // readable. The continuous strip is not paper -- it is trimmed to its
        // one system by `adjustPageHeight`, and those margins then become 20%
        // of the strip's height, which is 20% of the music's size on screen
        // for nothing. The left/right margins stay: they are the run-in before
        // the first clef and the run-out after the last bar.
        let vertical = continuous ? 10 : 100
        return """
        {"scale": 45, "footer": "none", \(breaks)
         "pageWidth": \(pageWidthTenthsMM), "pageHeight": \(pageHeightTenthsMM),
         "pageMarginTop": \(vertical), "pageMarginBottom": \(vertical),
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
        /// Pages that could not be drawn. The score still opens; these are what
        /// is missing from it.
        var failedPages: [Int] = []
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

    func engrave(musicXMLPath: String, layout: ScoreLayout = .page) throws -> Engraving {
        let continuous = layout.isContinuous
        let t = try tk()
        // BEFORE the load: Verovio lays the document out as it reads it, so
        // options set afterwards do not take until something reloads it -- and
        // on a score with no fingerings and no adjustments nothing does. Set
        // here, the very first continuous engrave is already continuous.
        _ = t.setOptions(Self.options(lyricSize: FingeringDiagrams.defaultLyricSize,
                                      continuous: continuous))
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
        _ = t.setOptions(Self.options(lyricSize: FingeringDiagrams.defaultLyricSize,
                                      continuous: continuous))

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
        // A mark is written to every part so the parts keep it; the combined
        // score would otherwise draw the letter once per staff, on top of
        // itself. render.py does the same on the export side.
        if let deduped = RehearsalMarks.meiWithDedupedMarks(mei) {
            mei = deduped
            reload = true
        }
        if reload {
            guard t.loadData(mei) else { throw RenderError.loadFailed(musicXMLPath) }
        }
        let document = PDFDocument()
        var rawPages: [String] = []
        /// Pages that could not be drawn, kept so the caller can say which.
        var failures: [RenderError] = []
        for page in 1...max(t.getPageCount(), 1) {
            // size is applied to the drawn glyph, because Verovio has no
            // per-element text size to ask for
            let svg = ChordAdjustments.applySizes(t.renderToSVG(page, true),
                                                  adjustments: adjustments)
            rawPages.append(svg)
            // A page that cannot be drawn is SKIPPED, not fatal. Throwing here
            // meant one unconvertible page threw away every good page with it:
            // a reader whose page 1 failed got no score at all rather than
            // pages 2 to 9. The pages that work are the point.
            let prepared = SVGForSwiftDraw.prepare(svg)
            guard !prepared.isEmpty else {
                failures.append(.pageEmpty(page)); continue
            }
            guard let parsed = SVG(data: Data(prepared.utf8)) else {
                failures.append(.pageUnconvertible(page)); continue
            }
            guard let pageData = try? parsed.pdfData(),
                  let pageDoc = PDFDocument(data: pageData),
                  let p = pageDoc.page(at: 0) else {
                failures.append(.pageUnconvertible(page)); continue
            }
            document.insert(p, at: document.pageCount)
        }
        // Only a score with NO drawable page at all is a failure.
        guard document.pageCount > 0, let data = document.dataRepresentation() else {
            throw failures.first ?? RenderError.nothingDrawn
        }
        // the same MEI the pages were drawn from, so addresses line up
        let geometry = try? ScoreModelBuilder.build(svgPages: rawPages, mei: mei)
        return Engraving(pdf: data,
                         failedPages: failures.compactMap(\.pageNumber),
                         geometry: geometry,
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

}
