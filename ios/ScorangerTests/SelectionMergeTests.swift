import CoreGraphics
import XCTest

/// §13's merge rule, and the three bugs it must not reopen.
final class SelectionMergeTests: XCTestCase {

    private func address(_ measure: Int, _ staff: Int, _ ordinal: Int,
                         kind: ScoreElementKind = .note) -> ScoreAddress {
        ScoreAddress(staff: staff, measure: measure, layer: 1,
                     kind: kind, ordinal: ordinal)
    }

    private func member(_ measure: Int, _ staff: Int, _ ordinal: Int,
                        _ frame: CGRect,
                        kind: ScoreElementKind = .note) -> SelectionMerge.Member {
        .init(address: address(measure, staff, ordinal, kind: kind), frame: frame)
    }

    private func key(_ measure: Int, _ staff: Int) -> SelectionMerge.Key {
        .init(measure: measure, staff: staff)
    }

    /// A complete bar is ONE mark, and its extent is the members' own -- not
    /// the bar's, not the system's.
    func testACompleteBarBecomesOneBoxOverItsOwnMembers() {
        let boxes = SelectionMerge.boxes(
            selected: [member(9, 2, 0, CGRect(x: 100, y: 50, width: 10, height: 20)),
                       member(9, 2, 1, CGRect(x: 140, y: 60, width: 10, height: 20))],
            population: [key(9, 2): 2])
        XCTAssertEqual(boxes.count, 1)
        XCTAssertEqual(boxes.first?.kind, .measure, "the 12% fill is keyed on this")
        XCTAssertEqual(boxes.first?.frame,
                       CGRect(x: 100, y: 50, width: 50, height: 30),
                       "the union must reach exactly as far as the members do")
    }

    /// Bug #9 and #10a: a `<measure>` in MEI spans every staff of the system,
    /// so a mark drawn at the bar's own frame lights music nobody selected.
    /// Asserted as a bound rather than by naming the frame: whatever the union
    /// is, it cannot be taller than what was selected.
    func testTheMarkNeverGrowsBeyondWhatWasSelected() {
        let members = [member(9, 2, 0, CGRect(x: 100, y: 300, width: 10, height: 20)),
                       member(9, 2, 1, CGRect(x: 140, y: 305, width: 10, height: 15))]
        let boxes = SelectionMerge.boxes(selected: members,
                                         population: [key(9, 2): 2])
        let selected = CGRect(x: 100, y: 300, width: 50, height: 20)
        XCTAssertEqual(boxes.count, 1)
        XCTAssertTrue(selected.contains(boxes[0].frame),
                      "the mark \(boxes[0].frame) reaches outside the selection "
                      + "\(selected) -- that is the whole-system bug")
    }

    /// Two complete bars are two marks. One rectangle over both would say
    /// something the reader did not ask for.
    func testSeveralBarsAreSeveralRectangles() {
        let boxes = SelectionMerge.boxes(
            selected: [member(9, 2, 0, CGRect(x: 100, y: 50, width: 10, height: 20)),
                       member(10, 2, 0, CGRect(x: 300, y: 50, width: 10, height: 20))],
            population: [key(9, 2): 1, key(10, 2): 1])
        XCTAssertEqual(boxes.count, 2)
        XCTAssertEqual(boxes.map(\.kind), [.measure, .measure])
        XCTAssertFalse(boxes[0].frame.intersects(boxes[1].frame),
                       "the two bars were merged into one rectangle")
    }

    /// And the same bar on two staves is two marks: the merge is per staff,
    /// or a triple-tap would paint a block down the system.
    func testOneBarOnTwoStavesIsTwoRectangles() {
        let boxes = SelectionMerge.boxes(
            selected: [member(9, 1, 0, CGRect(x: 100, y: 50, width: 10, height: 20)),
                       member(9, 2, 0, CGRect(x: 100, y: 400, width: 10, height: 20))],
            population: [key(9, 1): 1, key(9, 2): 1])
        XCTAssertEqual(boxes.count, 2)
        XCTAssertEqual(boxes.map(\.frame.minY).sorted(), [50, 400])
    }

    /// The union REPLACES the boxes. Drawn over them it would be a fourth
    /// multiplied layer on top of the compounding it exists to stop: two
    /// layers of 22% read as 39%, three as 53%.
    func testTheUnionReplacesTheBoxesRatherThanCoveringThem() {
        let boxes = SelectionMerge.boxes(
            selected: [member(9, 2, 0, CGRect(x: 100, y: 50, width: 10, height: 20)),
                       member(9, 2, 1, CGRect(x: 140, y: 50, width: 10, height: 20)),
                       member(9, 2, 2, CGRect(x: 180, y: 50, width: 10, height: 20))],
            population: [key(9, 2): 3])
        XCTAssertEqual(boxes.count, 1, "the member boxes are still being drawn")
    }

    /// A partly-selected bar is not a bar.
    func testAPartialBarKeepsItsIndividualBoxes() {
        let boxes = SelectionMerge.boxes(
            selected: [member(9, 2, 0, CGRect(x: 100, y: 50, width: 10, height: 20)),
                       member(9, 2, 1, CGRect(x: 140, y: 50, width: 10, height: 20))],
            population: [key(9, 2): 5])
        XCTAssertEqual(boxes.count, 2)
        XCTAssertEqual(boxes.map(\.kind), [.note, .note])
    }

    /// A bar the geometry says nothing about is never merged: silence is not
    /// completeness, and guessing here draws a rectangle over music that was
    /// never selected.
    func testAnUnknownBarIsNeverMerged() {
        let boxes = SelectionMerge.boxes(
            selected: [member(9, 2, 0, CGRect(x: 100, y: 50, width: 10, height: 20))],
            population: [:])
        XCTAssertEqual(boxes.count, 1)
        XCTAssertEqual(boxes.first?.kind, .note)
    }

    /// The same address twice -- a lasso adding what a tap already caught --
    /// must not add up to a bar that is not complete.
    func testARepeatedAddressDoesNotCompleteABar() {
        let one = member(9, 2, 0, CGRect(x: 100, y: 50, width: 10, height: 20))
        let boxes = SelectionMerge.boxes(selected: [one, one],
                                         population: [key(9, 2): 2])
        XCTAssertEqual(boxes.count, 2, "a duplicate was counted as a second note")
        XCTAssertEqual(boxes.map(\.kind), [.note, .note])
    }

    /// Mixed: one complete bar and one partial, in the same selection.
    func testACompleteBarAndAPartialOneAreDrawnDifferently() {
        let boxes = SelectionMerge.boxes(
            selected: [member(9, 2, 0, CGRect(x: 100, y: 50, width: 10, height: 20)),
                       member(10, 2, 0, CGRect(x: 300, y: 50, width: 10, height: 20)),
                       member(10, 2, 1, CGRect(x: 330, y: 50, width: 10, height: 20))],
            population: [key(9, 2): 1, key(10, 2): 4])
        XCTAssertEqual(boxes.map(\.kind), [.measure, .note, .note])
    }

    /// And the fill the merge exists to reach.
    func testTheMergedMarkDrawsAtTwelvePercentAndTheRestAtTwentyTwo() {
        XCTAssertEqual(SelectionInk.fillOpacity(for: .measure), 0.12)
        XCTAssertEqual(SelectionInk.fillOpacity(for: .note), 0.22)
    }
}
