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

    func testSubtractIsDrawnDifferentlyFromTheOthers() {
        XCTAssertNotEqual(SelectionCombine.subtract.strokeIsWarning,
                          SelectionCombine.add.strokeIsWarning,
                          "a lasso that removes must not look like one that adds")
        XCTAssertEqual(SelectionCombine.replace.strokeIsWarning,
                       SelectionCombine.add.strokeIsWarning)
    }
}
