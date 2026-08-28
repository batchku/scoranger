import XCTest

/// #44: a prompt transform on a selection blanked the whole canvas and lost the
/// selection, because the render path could not tell a new score from the same
/// score one op later.
final class RenderTransitionTests: XCTestCase {

    func testAnOpOnTheOpenScoreIsTheSameScore() {
        XCTAssertEqual(RenderTransition.between(previous: "blue-bossa/v003",
                                                next: "blue-bossa/v004"),
                       .sameScore)
    }

    func testOpeningADifferentArrangementIsADifferentScore() {
        XCTAssertEqual(RenderTransition.between(previous: "blue-bossa/v003",
                                                next: "morrisons-jig/v001"),
                       .differentScore)
    }

    func testTheFirstEngraveOfASessionIsFirst() {
        XCTAssertEqual(RenderTransition.between(previous: nil, next: "blue-bossa/v001"),
                       .first)
        XCTAssertEqual(RenderTransition.between(previous: "", next: "blue-bossa/v001"),
                       .first)
    }

    /// A forced re-render of exactly what is showing is not a change of
    /// subject either.
    func testARepeatOfTheSameKeyIsTheSameScore() {
        XCTAssertEqual(RenderTransition.between(previous: "blue-bossa/v003",
                                                next: "blue-bossa/v003"),
                       .sameScore)
    }

    /// Stepping BACK through the history is still the same music.
    func testPickingAnEarlierVersionIsTheSameScore() {
        XCTAssertEqual(RenderTransition.between(previous: "blue-bossa/v007",
                                                next: "blue-bossa/v002"),
                       .sameScore)
    }

    // MARK: what each one is allowed to throw away

    /// The half of #44 that is about the flash: an op must not take the page
    /// down. Its previous engraving is the same music, one op behind, and it
    /// stays up until the next one is ready.
    func testOnlyADifferentScoreBlanksTheCanvas() {
        XCTAssertFalse(RenderTransition.sameScore.blanksTheCanvas)
        XCTAssertFalse(RenderTransition.first.blanksTheCanvas)
        XCTAssertTrue(RenderTransition.differentScore.blanksTheCanvas)
    }

    /// The half about the selection, and about the page you were reading.
    func testOnlyADifferentScoreLosesTheReadersPlace() {
        XCTAssertTrue(RenderTransition.sameScore.keepsPlace)
        XCTAssertTrue(RenderTransition.first.keepsPlace)
        XCTAssertFalse(RenderTransition.differentScore.keepsPlace)
    }

    /// The rule the blanking was ADDED for, which must not be undone: opening
    /// an arrangement while another is on screen takes the other one down at
    /// once, rather than showing it and flipping.
    func testOpeningAnotherArrangementStillTakesTheOldOneDown() {
        let move = RenderTransition.between(previous: "blue-bossa/v003",
                                            next: "under-paris-skies/v001")
        XCTAssertTrue(move.blanksTheCanvas)
        XCTAssertFalse(move.keepsPlace)
    }

    /// A slug with a version-looking suffix must not be read as a version.
    func testAScoreWhoseSlugContainsDigitsIsStillItsOwnScore() {
        XCTAssertEqual(RenderTransition.between(previous: "study-no-2/v001",
                                                next: "study-no-3/v001"),
                       .differentScore)
        XCTAssertEqual(RenderTransition.between(previous: "study-no-2/v001",
                                                next: "study-no-2/v002"),
                       .sameScore)
    }
}
