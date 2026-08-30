import XCTest

/// The combined score draws a rehearsal mark once.
///
/// The engine writes one to EVERY part so that an extracted part keeps it, and
/// Verovio then anchors them all to the same staff of a combined score. Without
/// this, a four-part score draws "A" over itself four times.
final class RehearsalMarksTests: XCTestCase {
    private func mei(_ marks: [(bar: String, letter: String)]) -> String {
        var out = "<score><section>"
        var bars: [String: [String]] = [:]
        for mark in marks { bars[mark.bar, default: []].append(mark.letter) }
        for bar in bars.keys.sorted() {
            out += "<measure n=\"\(bar)\">"
            for letter in bars[bar] ?? [] {
                out += "<reh xml:id=\"r\(bar)\(letter)\" staff=\"1\"><rend>\(letter)</rend></reh>"
            }
            out += "<staff n=\"1\"/></measure>"
        }
        return out + "</section></score>"
    }

    private func count(_ text: String) -> Int {
        text.components(separatedBy: "<reh ").count - 1
    }

    func testFourPartsDrawOneMark() {
        let doubled = mei([("3", "A"), ("3", "A"), ("3", "A"), ("3", "A")])
        XCTAssertEqual(count(doubled), 4, "the fixture should start doubled")
        guard let deduped = RehearsalMarks.meiWithDedupedMarks(doubled) else {
            return XCTFail("nothing was deduped")
        }
        XCTAssertEqual(count(deduped), 1, "one mark should survive")
        XCTAssertTrue(deduped.contains(">A<"), "and it should still say A")
    }

    /// The property that lets one render path serve the score AND the parts.
    func testASinglePartIsLeftAlone() {
        let single = mei([("3", "A")])
        XCTAssertNil(RehearsalMarks.meiWithDedupedMarks(single),
                     "an extracted part must keep its mark, and needs no reload")
    }

    /// Different bars are different marks, however alike they look.
    func testMarksInDifferentBarsBothSurvive() {
        let two = mei([("3", "A"), ("3", "A"), ("9", "B"), ("9", "B")])
        guard let deduped = RehearsalMarks.meiWithDedupedMarks(two) else {
            return XCTFail("nothing was deduped")
        }
        XCTAssertEqual(count(deduped), 2, "one per bar, not one in total")
        XCTAssertTrue(deduped.contains(">A<") && deduped.contains(">B<"),
                      "both letters survive: \(deduped)")
    }

    /// Two DIFFERENT letters in one bar is not a duplicate. It should not
    /// happen, but silently eating one would hide the op that caused it.
    func testTwoDifferentLettersInOneBarAreBothKept() {
        let odd = mei([("3", "A"), ("3", "C")])
        XCTAssertNil(RehearsalMarks.meiWithDedupedMarks(odd),
                     "different letters are not duplicates of each other")
    }
}
