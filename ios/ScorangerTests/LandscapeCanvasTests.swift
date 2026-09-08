import XCTest

/// The music gets the screen, on a phone lying down.
///
/// Enabling landscape was one line of project.yml; this is the first thing it
/// broke. Measured on an iPhone 17 Pro at 874×402: the top bar ends at 44 and
/// the merged deck starts at 342, so the canvas has a 298pt band -- and the
/// page was drawn 140×182 inside it, centred, with most of the window empty.
///
/// It was not the chrome. E-B's merged deck was already built and already
/// correct at 48pt. It was the RESERVES: 24pt of outer margin and 84pt of
/// pill clearance, both sized for a 759pt-tall portrait screen, come to 108 of
/// 298 -- 36% of the band, taken before a note is drawn.
final class LandscapeCanvasTests: XCTestCase {

    private let phoneLandscape = CGSize(width: 874, height: 402)
    private let phonePortrait = CGSize(width: 393, height: 759)
    private let iPadLandscape = CGSize(width: 1210, height: 834)
    /// The band between the bar and the deck at 874×402, measured on device.
    private let band = CGSize(width: 874, height: 298)
    /// The engraved page this arrangement actually has.
    private let aspect: CGFloat = 1.294

    func testTheShortViewportIsThePhoneOnItsSide() {
        XCTAssertTrue(SpreadLayout.isShort(phoneLandscape))
        XCTAssertFalse(SpreadLayout.isShort(phonePortrait))
        XCTAssertFalse(SpreadLayout.isShort(iPadLandscape),
                       "an iPad in landscape has the room; it must keep the "
                       + "portrait reserves")
        XCTAssertFalse(SpreadLayout.isShort(.zero), "an unmeasured viewport is not short")
    }

    func testTheReservesShrinkOnlyWhereTheHeightCannotAffordThem() {
        XCTAssertEqual(SpreadLayout.margin(for: phoneLandscape), 6)
        XCTAssertEqual(SpreadLayout.margin(for: phonePortrait), SpreadLayout.margin)
        XCTAssertEqual(SpreadLayout.margin(for: iPadLandscape), SpreadLayout.margin)
        // the pill keeps its own 52pt of clearance -- a system under the pill
        // is a system nobody can read -- and loses the 32pt of comfort
        XCTAssertEqual(SpreadLayout.bottomChrome(for: phoneLandscape), 56)
        XCTAssertEqual(SpreadLayout.bottomChrome(for: phonePortrait),
                       SpreadLayout.bottomChrome)
        XCTAssertEqual(SpreadLayout.bottomChrome(for: iPadLandscape),
                       SpreadLayout.bottomChrome)
        XCTAssertGreaterThanOrEqual(SpreadLayout.bottomChrome(for: phoneLandscape),
                                    52,
                                    "the pill would be drawn over the music")
    }

    func testThePageNowFillsTheLandscapeBand() {
        let fitted = PagedCanvas.fittedPageWidth(
            viewport: band, pageAspect: aspect, pages: 1,
            gutter: SpreadLayout.gutter,
            margin: SpreadLayout.margin(for: band),
            bottomChrome: SpreadLayout.bottomChrome(for: band))
        let height = fitted * aspect
        // it was 182 of 402; the window's own 55% is 221
        XCTAssertGreaterThan(height, 221,
                             "the page is \(height)pt tall in a 402pt window")
        // and it cannot exceed what the band actually has
        XCTAssertLessThanOrEqual(height, band.height)
    }

    func testTheOldReservesAreWhatMadeItSmall() {
        // the same fit with portrait's numbers, to keep the cause on record
        let before = PagedCanvas.fittedPageWidth(
            viewport: band, pageAspect: aspect, pages: 1,
            gutter: SpreadLayout.gutter, margin: SpreadLayout.margin,
            bottomChrome: SpreadLayout.bottomChrome)
        XCTAssertLessThan(before * aspect, 200,
                          "portrait's reserves should still produce the small page")
    }

    func testPortraitIsUntouched() {
        let portraitBand = CGSize(width: 393, height: 600)
        let now = PagedCanvas.fittedPageWidth(
            viewport: portraitBand, pageAspect: aspect, pages: 1,
            gutter: SpreadLayout.gutter,
            margin: SpreadLayout.margin(for: portraitBand),
            bottomChrome: SpreadLayout.bottomChrome(for: portraitBand))
        let unchanged = PagedCanvas.fittedPageWidth(
            viewport: portraitBand, pageAspect: aspect, pages: 1,
            gutter: SpreadLayout.gutter, margin: SpreadLayout.margin,
            bottomChrome: SpreadLayout.bottomChrome)
        XCTAssertEqual(now, unchanged, "portrait must fit exactly as it did")
    }

    func testASpreadStillFitsAcrossTheLandscapeWidth() {
        // 874 wide is the one thing landscape has in abundance
        let two = PagedCanvas.fittedPageWidth(
            viewport: band, pageAspect: aspect, pages: 2,
            gutter: SpreadLayout.gutter,
            margin: SpreadLayout.margin(for: band),
            bottomChrome: SpreadLayout.bottomChrome(for: band))
        XCTAssertGreaterThan(two, 0)
        XCTAssertLessThanOrEqual(two * 2 + SpreadLayout.gutter
                                    + SpreadLayout.margin(for: band) * 2,
                                 band.width + 0.5)
    }
}
