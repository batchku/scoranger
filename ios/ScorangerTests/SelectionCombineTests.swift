import XCTest

/// How a new lasso combines with what is already selected.
///
/// Kept as arithmetic on addresses so it can be stated without a gesture: the
/// rejected alternative was "lassoing selected things toggles them out", which
/// cannot be tested meaningfully because its answer depends on what was caught
/// before, and cannot be explained to a user for the same reason.
final class SelectionCombineTests: XCTestCase {

    private func address(_ measure: Int, _ ordinal: Int = 0) -> ScoreAddress {
        ScoreAddress(staff: 1, measure: measure, layer: 1, kind: .note, ordinal: ordinal)
    }

    private func selection(_ measures: [Int]) -> ScoreSelection {
        ScoreSelection(addresses: measures.map { address($0) })
    }

    // MARK: - Replace

    func testReplaceKeepsOnlyWhatTheLassoCaught() {
        let result = selection([1, 2, 3]).combining([address(9)], mode: .replace)
        XCTAssertEqual(result.addresses, [address(9)])
    }

    func testReplaceWithNothingEmptiesTheSelection() {
        XCTAssertTrue(selection([1, 2]).combining([], mode: .replace).isEmpty)
    }

    // MARK: - Add

    func testAddUnionsWithWhatWasAlreadyThere() {
        let result = selection([1, 2]).combining([address(3)], mode: .add)
        XCTAssertEqual(result.addresses, [address(1), address(2), address(3)])
    }

    func testAddDoesNotListTheSameElementTwice() {
        let result = selection([1, 2]).combining([address(2), address(3)], mode: .add)
        XCTAssertEqual(result.addresses, [address(1), address(2), address(3)],
                       "lassoing over something already caught should not duplicate it")
    }

    func testAddKeepsTheOrderThingsWereSelectedIn() {
        let result = selection([5, 1]).combining([address(3)], mode: .add)
        XCTAssertEqual(result.addresses, [address(5), address(1), address(3)])
    }

    func testAddToAnEmptySelectionIsJustWhatWasCaught() {
        XCTAssertEqual(ScoreSelection(addresses: []).combining([address(4)], mode: .add).addresses,
                       [address(4)])
    }

    // MARK: - Subtract

    func testSubtractRemovesWhatTheLassoCaught() {
        let result = selection([1, 2, 3]).combining([address(2)], mode: .subtract)
        XCTAssertEqual(result.addresses, [address(1), address(3)])
    }

    func testSubtractLeavesUntouchedWhatItDidNotCatch() {
        let result = selection([1, 2]).combining([address(7), address(8)], mode: .subtract)
        XCTAssertEqual(result.addresses, [address(1), address(2)])
    }

    func testSubtractingEverythingEmptiesTheSelection() {
        let result = selection([1, 2]).combining([address(1), address(2)], mode: .subtract)
        XCTAssertTrue(result.isEmpty)
    }

    func testSubtractFromNothingStaysNothing() {
        XCTAssertTrue(ScoreSelection(addresses: [])
            .combining([address(1)], mode: .subtract).isEmpty)
    }

    // MARK: - Dropping one element, for a single correction

    func testDroppingOneAddressLeavesTheRest() {
        let result = selection([1, 2, 3]).dropping(address(2))
        XCTAssertEqual(result.addresses, [address(1), address(3)])
    }

    func testDroppingSomethingNotSelectedChangesNothing() {
        let result = selection([1, 2]).dropping(address(9))
        XCTAssertEqual(result.addresses, [address(1), address(2)])
    }

    // MARK: - The modes are distinguishable to the eye

    // MARK: - The mode may not outlive the selection it applies to

    /// Ali got stuck in Subtract and could not get out. The trap closes on
    /// itself: subtract empties the selection, an empty selection hides the
    /// chip, and the chip is the only way to change the mode -- so every
    /// later lasso subtracted from nothing and selected nothing, through
    /// score switches and version switches, until the app was relaunched.
    ///
    /// The rule that closes it: with nothing selected there is nothing to add
    /// to or take from, so the only mode that means anything is replace.
    func testAnEmptySelectionAlwaysReturnsToReplace() {
        XCTAssertEqual(SelectionCombine.modeAfter(.subtract, selectionIsEmpty: true),
                       .replace,
                       "subtract survived the selection it emptied")
        XCTAssertEqual(SelectionCombine.modeAfter(.add, selectionIsEmpty: true), .replace)
    }

    func testAChosenModeSurvivesWhileSomethingIsStillSelected() {
        XCTAssertEqual(SelectionCombine.modeAfter(.subtract, selectionIsEmpty: false),
                       .subtract)
        XCTAssertEqual(SelectionCombine.modeAfter(.add, selectionIsEmpty: false), .add)
    }

    /// The state the second screenshot shows: nothing selected, and a lasso
    /// that catches notes still yields nothing. It must be unreachable.
    func testALassoAlwaysSelectsSomethingWhenNothingWasSelectedBefore() {
        for mode in SelectionCombine.allCases {
            let effective = SelectionCombine.modeAfter(mode, selectionIsEmpty: true)
            let result = ScoreSelection(addresses: []).combining([address(15)], mode: effective)
            XCTAssertEqual(result.addresses, [address(15)],
                           "a lasso selected nothing with mode \(mode) and an empty selection")
        }
    }

    func testSubtractIsDrawnDifferentlyFromTheOthers() {
        XCTAssertNotEqual(SelectionCombine.subtract.strokeIsWarning,
                          SelectionCombine.add.strokeIsWarning,
                          "a lasso that removes must not look like one that adds")
        XCTAssertEqual(SelectionCombine.replace.strokeIsWarning,
                       SelectionCombine.add.strokeIsWarning)
    }

    // MARK: - A lasso never catches the bar it is drawn inside (#9, #10a)

    private func measureAddress(_ m: Int, staff: Int = 1) -> ScoreAddress {
        ScoreAddress(staff: staff, measure: m, layer: 1, kind: .measure, ordinal: 0)
    }

    /// A <measure> element's frame spans the whole bar across every staff, so
    /// a lasso over three notes caught the measure too and lit the entire bar
    /// (#9). One cause; the stray whole-bar selection from tapping empty space
    /// (#10a) is the same element caught the same way.
    func testALassoDropsTheBarAndKeepsTheNotes() {
        let caught = [address(15, 0), measureAddress(15), address(15, 1)]
        XCTAssertEqual(ScoreSelection.selectable(caught),
                       [address(15, 0), address(15, 1)])
    }

    func testALassoOverEmptySpaceCatchesNothingRatherThanTheWholeBar() {
        XCTAssertTrue(ScoreSelection.selectable([measureAddress(15)]).isEmpty)
    }

    func testNotesAreUntouchedByTheFilter() {
        let notes = [address(1), address(2), address(3)]
        XCTAssertEqual(ScoreSelection.selectable(notes), notes)
    }

    // MARK: - What the chip says (#4a, #4b)

    func testTheHeadlineCountsAndNamesTheBar() {
        XCTAssertEqual(selection([15, 15, 15]).headline, "3 elements from bar 15")
    }

    func testOneElementIsNotPluralised() {
        XCTAssertEqual(selection([15]).headline, "1 element from bar 15")
    }

    func testASelectionSpanningBarsSaysSo() {
        XCTAssertEqual(selection([15, 16, 17]).headline, "3 elements from bars 15–17")
    }

    func testTheChipNamesTheStaffAndVoice() {
        let s = ScoreSelection(addresses: [
            ScoreAddress(staff: 3, measure: 15, layer: 2, kind: .note, ordinal: 0)])
        XCTAssertEqual(s.placeLine, "staff 3 · voice 2")
    }

    func testASelectionAcrossStavesListsThem() {
        let s = ScoreSelection(addresses: [
            ScoreAddress(staff: 1, measure: 15, layer: 1, kind: .note, ordinal: 0),
            ScoreAddress(staff: 2, measure: 15, layer: 1, kind: .note, ordinal: 0)])
        XCTAssertEqual(s.placeLine, "staves 1, 2 · voice 1")
    }

    // MARK: - The addresses an op is scoped to (#7)

    /// The list handed to the engine has to be exactly what was selected, in
    /// the engine's own address syntax -- this is the string that decides
    /// which notes get transposed.
    func testTheAddressListIsTheEnginesSyntax() {
        let s = ScoreSelection(addresses: [
            ScoreAddress(staff: 1, measure: 15, layer: 1, kind: .note, ordinal: 3)])
        XCTAssertEqual(s.addressList, ["s1/m15/l1/note#3"])
    }

    // MARK: - When a selection may outlive a re-engrave (#8)

    /// #8 asks for the selection to survive an op, so a second op can be run
    /// on the same notes. It must NOT survive being taken somewhere else --
    /// and both arrive at the renderer as "the version changed".
    ///
    /// The rule: same arrangement, and the user did not ask for the version.

    func testASelectionSurvivesANewVersionOfTheSameScore() {
        XCTAssertTrue(ScoreSelection.survivesReRender(
            from: "morrisons/v007", to: "morrisons/v008", userPickedVersion: false))
    }

    func testASelectionDoesNotSurviveADeliberateVersionSwitch() {
        XCTAssertFalse(ScoreSelection.survivesReRender(
            from: "morrisons/v007", to: "morrisons/v003", userPickedVersion: true),
                       "looking at an older version is a different subject")
    }

    func testASelectionDoesNotSurviveSwitchingArrangement() {
        XCTAssertFalse(ScoreSelection.survivesReRender(
            from: "morrisons/v007", to: "morrisons-copy/v001", userPickedVersion: false),
                       "this is exactly the bleed between a score and its copy")
    }

    func testASelectionWithNoPriorEngravingDoesNotSurvive() {
        XCTAssertFalse(ScoreSelection.survivesReRender(
            from: nil, to: "morrisons/v008", userPickedVersion: false))
    }
}
