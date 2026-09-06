import CoreGraphics
import SwiftUI
import XCTest

/// §14.5's acceptance, and the bug it is written against.
///
/// Ali's row was clipped at both edges on a phone because it had no yield
/// order: whatever it wanted, it drew, and SwiftUI centred the overflow. These
/// are the same two claims the score bar's fix needed -- what it seats, it can
/// draw; and everything stays reachable -- asked of the row that did not get
/// that treatment.
final class LibraryBarLayoutTests: XCTestCase {

    /// Every real width a library row gets, from the narrowest phone to a
    /// 13-inch iPad, with the sidePadding already taken off.
    private static let widths: [(String, CGFloat)] = [
        ("iPhone SE portrait", 375 - 40),
        ("iPhone 15 portrait", 393 - 40),
        ("iPhone 17 Pro portrait", 402 - 40),
        ("iPhone landscape", 734 - 40),
        ("iPad split narrow", 507 - 40),
        ("iPad 11 portrait", 834 - 40),
        ("iPad 13 landscape", 1366 - 40),
    ]

    // MARK: - 1. It seats what it can draw

    /// The whole of the bug, as one assertion: for every width, every sort and
    /// every text size, what the row seats must fit in the row.
    ///
    /// The sort matters and is not decoration -- "Sort: recently changed" is
    /// far wider than "Sort: name", so the row overflowed under one sort and
    /// not another. A fix that held only for the selected sort would be no fix.
    func testItSeatsOnlyWhatItCanDraw() {
        for (name, width) in Self.widths {
            for sort in LibrarySort.allCases {
                for size in DynamicTypeSize.allCases {
                    let labels = LibraryBarMetrics.labels(
                        sort: sort, filters: 0, editing: false, size: size)
                    let fit = LibraryBarLayout.fit(
                        width: width, labels: labels,
                        accessibilitySize: size.isAccessibilitySize)
                    // A wrapped or listed row is not claiming to fit on one
                    // line, so the width claim applies to the rest.
                    guard !fit.wraps, !fit.list else { continue }
                    let needed = LibraryBarLayout.width(of: fit, labels: labels)
                    XCTAssertLessThanOrEqual(
                        needed, width,
                        "\(name) at \(Int(width))pt, sort \(sort), \(size): "
                        + "seats \(Int(needed))pt it cannot draw -- \(fit)")
                }
            }
        }
    }

    /// The bug itself, so this suite would have failed before the fix: the row
    /// as it shipped -- five labelled-then-iconised actions with a full sort --
    /// does not fit a phone, and the layout must not claim it does.
    func testThePhoneDoesNotFitEverything() {
        let labels = LibraryBarMetrics.labels(sort: .recent, filters: 0,
                                              editing: false, size: .large)
        let everything = LibraryBarLayout.Fit()
        XCTAssertFalse(
            LibraryBarLayout.fits(everything, in: 393 - 40, labels: labels),
            "a phone is being told it can draw the whole row: "
            + "\(Int(LibraryBarLayout.width(of: everything, labels: labels)))pt "
            + "in \(393 - 40)pt")
    }

    // MARK: - 2. The order, and what it protects

    /// Labels yield in the stated order, and Sort's answer goes LAST because
    /// that label being an answer is the reason it is written that way.
    func testLabelsYieldInTheStatedOrder() {
        let labels = LibraryBarMetrics.labels(sort: .recent, filters: 0,
                                              editing: false, size: .large)
        var seen: [String] = []
        var width = LibraryBarLayout.width(of: LibraryBarLayout.Fit(),
                                           labels: labels)
        // Walk the row narrower one point at a time and record what goes.
        var last = LibraryBarLayout.Fit()
        while width > 200 {
            width -= 1
            let fit = LibraryBarLayout.fit(width: width, labels: labels)
            if fit.editLabelled != last.editLabelled { seen.append("edit") }
            if fit.filterLabelled != last.filterLabelled { seen.append("filter") }
            if fit.newLabelled != last.newLabelled { seen.append("new") }
            if fit.importLabelled != last.importLabelled { seen.append("import") }
            if fit.sort != last.sort { seen.append("sort:\(fit.sort)") }
            last = fit
        }
        XCTAssertEqual(seen, ["edit", "filter", "new", "import",
                              "sort:short", "sort:bare"],
                       "the row gave things up in the wrong order: \(seen)")
    }

    /// A phone under the LONGEST sort still fits on one line, which is the
    /// case §14.1 measured at 138pt over.
    func testThePhoneFitsUnderTheLongestSort() {
        let labels = LibraryBarMetrics.labels(sort: .arrangements, filters: 0,
                                              editing: false, size: .large)
        let fit = LibraryBarLayout.fit(width: 375 - 40, labels: labels)
        XCTAssertFalse(fit.wraps,
                       "the narrowest phone wraps under the longest sort even "
                       + "after every label has yielded")
        XCTAssertTrue(LibraryBarLayout.fits(fit, in: 375 - 40, labels: labels))
    }

    /// An iPad gives nothing up: the row it was designed with is the row it
    /// draws.
    func testAnIPadKeepsEveryLabel() {
        let labels = LibraryBarMetrics.labels(sort: .recent, filters: 0,
                                              editing: false, size: .large)
        let fit = LibraryBarLayout.fit(width: 1366 - 40, labels: labels)
        XCTAssertEqual(fit, LibraryBarLayout.Fit(),
                       "an iPad is yielding labels it has room for")
    }

    // MARK: - 3. Two rows is the floor, and the list is the rule

    /// At an accessibility size the row is a vertical list, whatever it would
    /// have measured -- §6.3 rule 4 applies to this row like every other.
    func testAnAccessibilitySizeBecomesAList() {
        for size in DynamicTypeSize.allCases where size.isAccessibilitySize {
            let labels = LibraryBarMetrics.labels(sort: .name, filters: 0,
                                                  editing: false, size: size)
            let fit = LibraryBarLayout.fit(width: 353, labels: labels,
                                           accessibilitySize: true)
            XCTAssertTrue(fit.list, "\(size) is still drawing a single row")
            XCTAssertFalse(fit.wraps, "a list does not also wrap")
        }
    }

    /// And a row too narrow for even the bare form wraps rather than
    /// overflowing -- which is the failure this whole file is about.
    func testAnImpossibleWidthWrapsRatherThanOverflowing() {
        let labels = LibraryBarMetrics.labels(sort: .arrangements, filters: 3,
                                              editing: true, size: .xxxLarge)
        let fit = LibraryBarLayout.fit(width: 120, labels: labels)
        XCTAssertTrue(fit.wraps, "120pt claims to hold the whole row on a line")
    }

    /// Measured, not assumed: the label widths must actually grow with the
    /// text size, or the arithmetic is back to being literals.
    func testTheLabelWidthsAreMeasuredAtTheTextSize() {
        let small = LibraryBarMetrics.labels(sort: .recent, filters: 0,
                                             editing: false, size: .large)
        let big = LibraryBarMetrics.labels(sort: .recent, filters: 0,
                                           editing: false, size: .xxxLarge)
        XCTAssertGreaterThan(big.sortFull, small.sortFull,
                             "the sort label did not grow with the text size")
        XCTAssertGreaterThan(big.iconButton, small.iconButton,
                             "the icon button did not grow with the text size")
        XCTAssertGreaterThan(small.sortFull, small.sortShort,
                             "the short sort label is not shorter")
        XCTAssertGreaterThan(small.sortShort, small.sortBare)
    }
}
