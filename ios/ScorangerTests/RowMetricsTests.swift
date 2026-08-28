import XCTest

/// A library row's ☰ is drawn as an OVERLAY on its trailing edge -- it has to
/// be, since the row itself is a button and a button inside a button's label
/// cannot be tapped. An overlay is outside the layout, so the row's own
/// content knows nothing about it and ran underneath: Ali's screenshot has
/// "v001 · 3 Aug" and the chevron sitting under the ☰.
///
/// The fix is a reserved inset, and the thing that can silently undo it is
/// someone changing the button's size or its padding without changing the
/// reservation. That is what this holds together.
final class RowMetricsTests: XCTestCase {

    /// `RowMenuButton` is one hit target wide, and `LRow` pads it `s8` from
    /// the trailing edge.
    func testARowReservesRoomForTheMenuOverlaidOnIt() {
        let overlaid = Theme.Metric.hitTarget + Theme.Metric.s8
        XCTAssertGreaterThanOrEqual(
            Theme.Metric.rowMenuInset, overlaid,
            "a row's content would run under its ☰ again")
    }

    /// ...and a gap, so the metadata is not merely touching the ☰.
    func testTheReservationLeavesAGapNotJustClearance() {
        XCTAssertGreaterThanOrEqual(
            Theme.Metric.rowMenuInset - (Theme.Metric.hitTarget + Theme.Metric.s8),
            Theme.Metric.s8)
    }
}
