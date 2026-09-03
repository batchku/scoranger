import CoreGraphics
import Foundation

/// The Verovio option set for one layout, as the JSON string the toolkit takes.
///
/// Pure, and here rather than inside `VerovioRenderer`, because the bug this
/// type exists to prevent is not visible in a picture of the render: it is what
/// Verovio DOES with two option sets given one after the other.
///
/// ## setOptions MERGES; it does not replace
///
/// Verovio's `setOptions` sets the options the JSON names and leaves every
/// other option at whatever it already was. It does not reset the rest to
/// their defaults.
///
/// The two option sets used to differ by naming `breaks` in the continuous one
/// and not naming it at all in the paged one. So the first continuous engrave
/// set `breaks: "none"` on the shared toolkit and NOTHING ever set it back:
/// every paged engrave for the rest of the process laid the whole score out as
/// one system on one enormous page. Measured on the nine-page arrangement in
/// the workspace, in the engine's own Verovio:
///
///     fresh toolkit  -> paged options        9 pages, breaks = auto
///     fresh toolkit  -> continuous options   1 page,  breaks = none
///     the same one   -> paged options        1 page,  breaks = none   <-- the bug
///     with breaks named in the paged set     9 pages, breaks = auto
///
/// That one line is the root of three reported faults. Pagination gone and the
/// counter reading "p. 1 / 1" is the page count above. Blur is that same strip
/// -- 17000pt wide -- rastered through the paged canvas, which caps a page at
/// 5200px and so drew it at a quarter resolution; the shading flip between one
/// page and two is the same cap landing on a different size. Garbled thumbnails
/// are the whole score squeezed into a page-shaped box.
///
/// So: **every option that differs between the layouts is named in BOTH sets.**
/// Anything else is a value one layout can leave behind for the other to find.
enum EngravingOptions {

    /// A page is a FIXED size: US Letter portrait, which is what the sources
    /// are. Verovio lays out in TENTHS OF A MILLIMETRE -- its own A4 default,
    /// 2100 x 2970, is 210 x 297mm -- so US Letter is 2159 x 2794. Mirrors
    /// render.py's PAGE_WIDTH_TENTHS_MM / PAGE_HEIGHT_TENTHS_MM; keep the two
    /// in step.
    static let pageWidthTenthsMM = 2159
    static let pageHeightTenthsMM = 2794

    /// The engraving scale, as a percentage. Also the conversion from Verovio's
    /// tenths of a millimetre to the points it emits: Verovio writes the page
    /// as `units * scale/100` pixels.
    static let scale = 45

    /// The engraved page in the PDF's own points, which is what the canvas
    /// measures and what `ContinuousTiles` needs in order to say how big a
    /// notehead is on a fitted page. 2159 x 0.45 = 971.55, and Verovio's own
    /// SVG for these options reports 972 x 1258.
    static var pageSize: CGSize {
        CGSize(width: CGFloat(pageWidthTenthsMM) * CGFloat(scale) / 100,
               height: CGFloat(pageHeightTenthsMM) * CGFloat(scale) / 100)
    }

    /// How Verovio breaks systems, per layout.
    ///
    /// `none` puts every system on one line and is what makes the continuous
    /// surface a strip. `auto` is Verovio's own line and page breaking, and is
    /// what `render.py` exports with -- so a page on the iPad and a page in an
    /// exported PDF are broken the same way.
    static func breaks(continuous: Bool) -> String { continuous ? "none" : "auto" }

    /// A page's top and bottom margins are paper: they keep a printed page
    /// readable. The continuous strip is not paper -- it is trimmed to its one
    /// system by `adjustPageHeight`, and those margins then become 20% of the
    /// strip's height, which is 20% of the music's size on screen for nothing.
    /// The left/right margins stay: they are the run-in before the first clef
    /// and the run-out after the last bar.
    static func verticalMargin(continuous: Bool) -> Int { continuous ? 10 : 100 }

    /// `adjustPageHeight` trims the page to its own content. On the strip that
    /// is what makes it a strip. On paper it is wrong: a page holding less
    /// music would be a SHORTER page, and a two-page spread would show the left
    /// leaf's bottom edge above the right's.
    static func adjustPageHeight(continuous: Bool) -> Bool { continuous }

    /// The whole option set, with every layout-dependent option named.
    static func json(lyricSize: Double, continuous: Bool) -> String {
        """
        {"scale": \(scale), "footer": "none",
         "breaks": "\(breaks(continuous: continuous))",
         "adjustPageHeight": \(adjustPageHeight(continuous: continuous)),
         "pageWidth": \(pageWidthTenthsMM), "pageHeight": \(pageHeightTenthsMM),
         "pageMarginTop": \(verticalMargin(continuous: continuous)),
         "pageMarginBottom": \(verticalMargin(continuous: continuous)),
         "pageMarginLeft": 120, "pageMarginRight": 120,
         "lyricSize": \(lyricSize)}
        """
    }

    /// The keys that must appear in EVERY option set, whatever the layout.
    ///
    /// Named here so the test asserting it is asserting a rule rather than a
    /// list someone happened to type twice.
    static let layoutDependentKeys = ["breaks", "adjustPageHeight",
                                      "pageMarginTop", "pageMarginBottom"]
}
