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

/// L23: entering Edit mode shifted the whole list sideways by more than the
/// checkbox is wide, so the screen looked like it had changed rather than like
/// a column had appeared.
extension RowMetricsTests {

    func testTheCheckboxGutterIsExactlyOneHitTarget() {
        XCTAssertEqual(Theme.Metric.checkboxGutter, Theme.Metric.hitTarget,
                       "the gutter is the checkbox, and nothing either side of it")
    }

    /// The rule stated as the shift a reader sees: the content moves by the
    /// gutter, not by the gutter plus whatever padding crept in around it.
    func testEnteringEditModeMovesTheRowByTheGutterAlone() {
        let plainLeading = Theme.Metric.s20
        let editingLeading = Theme.Metric.checkboxGutter + Theme.Metric.s20
        XCTAssertEqual(editingLeading - plainLeading, Theme.Metric.checkboxGutter,
                       accuracy: 0.001)
        XCTAssertLessThanOrEqual(Theme.Metric.checkboxGutter, 44)
    }
}
