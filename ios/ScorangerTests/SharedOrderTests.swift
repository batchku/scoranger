import XCTest

/// The running order two people can edit at once (`SharedOrder`).
///
/// design/FIREBASE.md §6.5. The property that matters is one line: the key
/// returned is strictly between its neighbours, by string comparison, always.
/// Everything else here is that property under the conditions that break naive
/// implementations -- repeated insertion in the same gap, insertion at either
/// end, and the case where two keys are adjacent characters with no room
/// between them.
final class SharedOrderTests: XCTestCase {

    /// The invariant, asserted directly.
    private func assertBetween(_ key: String, _ before: String?, _ after: String?,
                               _ message: String = "", line: UInt = #line) {
        if let before { XCTAssertGreaterThan(key, before, "\(message) not after \(before)", line: line) }
        if let after { XCTAssertLessThan(key, after, "\(message) not before \(after)", line: line) }
    }

    func testAnEmptyListGetsAKeyInTheMiddleOfTheAlphabet() {
        let only = SharedOrder.between(nil, nil)
        XCTAssertFalse(only.isEmpty)
        // Not the first character: a key at the bottom leaves no room to insert
        // before it without lengthening, and the first thing anyone does to a
        // setlist is put something at the top.
        XCTAssertGreaterThan(only, String(SharedOrder.alphabet.first!))
        XCTAssertLessThan(only, String(SharedOrder.alphabet.last!))
    }

    func testAppendingKeepsGoingUp() {
        var keys: [String] = []
        var previous: String? = nil
        for i in 0..<200 {
            let key = SharedOrder.between(previous, nil)
            assertBetween(key, previous, nil, "append \(i)")
            keys.append(key)
            previous = key
        }
        XCTAssertEqual(keys, keys.sorted(), "appending did not produce an ascending list")
        XCTAssertEqual(Set(keys).count, keys.count, "appending produced a duplicate")
    }

    func testPrependingKeepsGoingDown() {
        var keys: [String] = []
        var next: String? = nil
        for i in 0..<200 {
            let key = SharedOrder.between(nil, next)
            assertBetween(key, nil, next, "prepend \(i)")
            keys.append(key)
            next = key
        }
        XCTAssertEqual(keys, keys.sorted().reversed(), "prepending did not descend")
        XCTAssertEqual(Set(keys).count, keys.count, "prepending produced a duplicate")
    }

    /// The one that kills a double-based implementation: insert repeatedly into
    /// the SAME gap. A double runs out of mantissa after about fifty of these
    /// and the order stops being editable; a string just gets longer.
    func testInsertingRepeatedlyIntoTheSameGapNeverRunsOut() {
        let low = SharedOrder.between(nil, nil)
        let high = SharedOrder.between(low, nil)
        var upper = high
        for i in 0..<500 {
            let key = SharedOrder.between(low, upper)
            assertBetween(key, low, upper, "squeeze \(i)")
            upper = key
        }
        XCTAssertLessThan(upper.count, 400,
                          "the key grew a character per insertion; the encoding "
                          + "is not halving the gap")
    }

    /// Adjacent characters with nothing between them -- "a" and "b" -- still
    /// admit a key, by going deeper rather than by giving up.
    func testAdjacentKeysStillAdmitOneBetweenThem() {
        assertBetween(SharedOrder.between("a", "b"), "a", "b")
        assertBetween(SharedOrder.between("0", "1"), "0", "1")
        assertBetween(SharedOrder.between("y", "z"), "y", "z")
        // and where one is a prefix of the other
        assertBetween(SharedOrder.between("a", "aa"), "a", "aa")
        assertBetween(SharedOrder.between("a", "ab"), "a", "ab")
    }

    /// A setlist that arrives whole gets keys with room between them, so the
    /// first reorder does not immediately have to lengthen one.
    func testAWholeSetlistIsSpreadInOrder() {
        let keys = SharedOrder.spread(count: 12)
        XCTAssertEqual(keys.count, 12)
        XCTAssertEqual(keys, keys.sorted(), "spread was not ascending")
        XCTAssertEqual(Set(keys).count, 12, "spread produced a duplicate")
        for (a, b) in zip(keys, keys.dropFirst()) {
            assertBetween(SharedOrder.between(a, b), a, b, "gap between \(a) and \(b)")
        }
        XCTAssertEqual(SharedOrder.spread(count: 0), [])
    }

    /// TWO PEOPLE, DIFFERENT ENTRIES: both moves survive. This is the whole
    /// reason for the design -- with an array on the parent document, one of
    /// these two writes would silently discard the other.
    func testTwoEditorsMovingDifferentEntriesBothSurvive() {
        // A B C D E, and each entry owns its key
        var order = Dictionary(uniqueKeysWithValues:
            zip(["A", "B", "C", "D", "E"], SharedOrder.spread(count: 5)))
        func sorted() -> [String] { order.sorted { $0.value < $1.value }.map(\.key) }
        XCTAssertEqual(sorted(), ["A", "B", "C", "D", "E"])

        // Aisha moves E to the front; Ben moves A to the end. Neither reads the
        // other's write, which is what concurrent means.
        let eKey = SharedOrder.between(nil, order["A"]!)
        let aKey = SharedOrder.between(order["E"]!, nil)
        order["E"] = eKey       // both land, in either arrival order
        order["A"] = aKey

        XCTAssertEqual(sorted(), ["E", "B", "C", "D", "A"],
                       "one editor's move was lost")
    }

    /// TWO PEOPLE, THE SAME ENTRY: last writer wins, and there is no third
    /// state. Correct and unsurprising (§6.5).
    func testTwoEditorsMovingTheSameEntryEndWithOneOfTheTwoPlacements() {
        var order = Dictionary(uniqueKeysWithValues:
            zip(["A", "B", "C"], SharedOrder.spread(count: 3)))
        let toFront = SharedOrder.between(nil, order["A"]!)
        let toBack = SharedOrder.between(order["C"]!, nil)

        order["B"] = toFront
        order["B"] = toBack     // the later write
        let sorted = order.sorted { $0.value < $1.value }.map(\.key)
        XCTAssertEqual(sorted, ["A", "C", "B"])
        XCTAssertTrue(order["B"] == toBack, "the later placement did not win")
    }

    /// Every key is comparable as a plain string on any device: digits and
    /// lower case only, so no collation or locale can reorder them.
    func testKeysUseOnlyAsciiOrderedCharacters() {
        let produced = SharedOrder.spread(count: 40)
            + (0..<40).map { _ in SharedOrder.between("a", "b") }
        for key in produced {
            XCTAssertTrue(key.allSatisfy { SharedOrder.alphabet.contains($0) },
                          "\(key) has a character outside the alphabet")
        }
    }
}
