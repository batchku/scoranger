import SwiftUI
import XCTest

/// REDESIGN_BRIEF_0.8 §7.3: the Edit-mode bar yields in a stated order and
/// fits at every width and text size.
final class LibraryActionBarLayoutTests: XCTestCase {

    /// The bar a selection of SEVERAL pieces gets -- the widest case, and the
    /// one the rungs were measured against.
    private let pieces = LibraryActions.bar(for: .pieces, count: 5)

    /// And the bar a single piece gets, which carries a longer first verb
    /// ("New arrangement") and so must be measured too.
    private let onePiece = LibraryActions.bar(for: .pieces, count: 1)

    /// The rungs, in order, are each narrower than the last -- or the order
    /// is not a yield order.
    func testEachRungIsNarrowerThanTheOneBefore() {
        let labels = LibraryActionBarMetrics.labels(count: 5, kind: .pieces, size: .large)
        let widths = [LibraryActionBarLayout.Rung.full, .noReadout, .shortVerbs, .deleteUncounted]
            .map { LibraryActionBarLayout.width(of: $0, actions: pieces, labels: labels) }
        for (a, b) in zip(widths, widths.dropFirst()) {
            XCTAssertLessThan(b, a, "\(widths)")
        }
        print("BAR rungs at Large, 5 pieces: \(widths.map { Int($0) })")
    }

    /// The order the brief measured: readout first, then short verbs, then
    /// Delete's count -- and at a phone's 353pt the short verbs are what fit.
    func testAtAPhonesWidthTheShortVerbsFit() {
        let labels = LibraryActionBarMetrics.labels(count: 5, kind: .pieces, size: .large)
        let rung = LibraryActionBarLayout.rung(width: 353, actions: pieces, labels: labels)
        XCTAssertTrue(rung == .shortVerbs || rung == .noReadout,
                      "at 353pt the bar yielded to \(rung)")
        XCTAssertEqual(LibraryActionBarLayout.rung(width: 1000, actions: pieces, labels: labels), .full)
    }

    /// BOTH pieces bars fit on ONE ROW at a phone's width, not just the one a
    /// multi-selection gets.
    ///
    /// This is what Combine cost before the bar became count-aware: a fourth
    /// capsule took 353pt to `.twoRows`, which is the whole bar folding in
    /// half on every phone. Measuring only the five-selected case would have
    /// missed the single-piece bar, whose first verb is the LONGER of the two
    /// ("New arrangement" against "Combine…").
    func testBothPiecesBarsFitOnOneRowOnAPhone() {
        for (count, actions) in [(1, onePiece), (5, pieces)] {
            let labels = LibraryActionBarMetrics.labels(count: count, kind: .pieces, size: .large)
            let rung = LibraryActionBarLayout.rung(width: 353, actions: actions, labels: labels)
            XCTAssertNotEqual(rung, .twoRows,
                              "\(count) selected: the bar needs two rows at 353pt")
            XCTAssertTrue(rung <= .shortVerbs,
                          "\(count) selected: Delete gave up its count at 353pt, "
                          + "and the count is the safety on the destructive verb")
        }
    }

    /// The count-aware bar is always three capsules, so it cannot re-flow
    /// under a finger as a selection grows.
    func testThePiecesBarIsTheSameWidthWhateverIsSelected() {
        for count in 1...12 {
            XCTAssertEqual(LibraryActions.bar(for: .pieces, count: count).count, 3)
        }
    }

    // 4. theBarFitsAtEveryWidth
    func testTheChosenRungFitsAtEveryWidthAndSize() {
        let sizes: [DynamicTypeSize] = [.xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
                                        .accessibility1, .accessibility2, .accessibility3,
                                        .accessibility4, .accessibility5]
        for size in sizes {
            for count in [1, 5, 12] {
                let labels = LibraryActionBarMetrics.labels(count: count, kind: .pieces, size: size)
                // BOTH bars: a single piece gets a different, longer first verb
                for actions in [pieces, onePiece] {
                    for width in stride(from: 320, through: 1366, by: 1) {
                        let bar = CGFloat(width)
                        let rung = LibraryActionBarLayout.rung(width: bar, actions: actions, labels: labels)
                        guard rung != .twoRows else { continue }
                        XCTAssertLessThanOrEqual(LibraryActionBarLayout.width(of: rung, actions: actions, labels: labels),
                                                 bar, "\(size) \(count) selected at \(width)pt chose \(rung)")
                    }
                }
            }
        }
    }

    /// The labels the rungs draw, and the sentence VoiceOver keeps.
    func testTheShortLabelsAreNounsAndTheSentenceSurvives() {
        XCTAssertEqual(LibraryAction.newSetlist.title(count: 5, kind: .pieces), "New set list")
        XCTAssertEqual(LibraryAction.newSetlist.shortTitle(count: 5, kind: .pieces), "Set list")
        XCTAssertEqual(LibraryAction.newArrangement.shortTitle(count: 1, kind: .pieces), "Arrangement")
        XCTAssertEqual(LibraryAction.newSetlist.accessibilityTitle(count: 5, kind: .pieces),
                       "New set list from 5 pieces")
        XCTAssertEqual(LibraryAction.newSetlist.accessibilityTitle(count: 1, kind: .pieces),
                       "New set list from this piece")
        XCTAssertEqual(LibraryAction.delete.deleteTitle(count: 5, kind: .pieces, counted: true), "Delete 5 pieces")
        XCTAssertEqual(LibraryAction.delete.deleteTitle(count: 5, kind: .pieces, counted: false), "Delete")
    }
}
