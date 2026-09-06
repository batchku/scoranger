import XCTest

/// How strongly a selection box is filled, and why it is not one number.
///
/// IPHONE_0.6.14 §11, from the designer: the shipped values stay -- `clay` at
/// 22% with a `clayStrong` border at 65% -- with ONE change. A measure's fill
/// drops to 12%.
///
/// The reason is area, not taste. A bar box is roughly fifty times a
/// notehead's, and 22% across a whole bar is a wash: the tint stops reading as
/// a highlight and starts reading as a stain on the page. At 12% the area does
/// the work and the border carries the definition, which is what a border is
/// for.
final class SelectionFillTests: XCTestCase {

    /// A notehead keeps the shipped 22%.
    func testANoteKeepsItsFill() {
        for kind in ScoreElementKind.noteLike {
            XCTAssertEqual(SelectionInk.fillOpacity(for: kind), 0.22,
                           accuracy: 0.001, "\(kind)")
        }
    }

    /// A bar is filled at 12%, because it is fifty times the area.
    func testAMeasureIsFilledMoreLightly() {
        XCTAssertEqual(SelectionInk.fillOpacity(for: .measure), 0.12,
                       accuracy: 0.001)
    }

    /// Markings -- a chord symbol, a dynamic, a slur -- are notehead-sized
    /// objects and take the notehead's fill. Only the bar is a wash.
    func testMarkingsAreFilledLikeNotes() {
        for kind in ScoreElementKind.markingLike {
            XCTAssertEqual(SelectionInk.fillOpacity(for: kind), 0.22,
                           accuracy: 0.001, "\(kind)")
        }
    }

    /// The lighter fill is genuinely lighter, which is the whole claim.
    func testTheBarIsLighterThanTheNote() {
        XCTAssertLessThan(SelectionInk.fillOpacity(for: .measure),
                          SelectionInk.fillOpacity(for: .note))
    }

    /// Every kind answers. A kind with no opacity would draw an invisible
    /// selection, which is worse than a wrong one because nothing says so.
    func testEveryKindHasAFill() {
        for kind in ScoreElementKind.allCases {
            XCTAssertGreaterThan(SelectionInk.fillOpacity(for: kind), 0,
                                 "\(kind) draws no fill at all")
        }
    }

    /// The border is one value at every granularity: it is what carries
    /// definition when the fill lets go, so it must not weaken with the fill.
    func testTheBorderDoesNotFollowTheFill() {
        XCTAssertEqual(SelectionInk.borderOpacity, 0.65, accuracy: 0.001)
    }
}
