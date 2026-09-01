import XCTest

/// Two devices appending to one history (`VersionGraph`).
///
/// This is the case stage 0 was done for. While a version's key was
/// `v{count + 1}` two offline devices both allocated `v031` and one of them had
/// to be renumbered or dropped -- neither explicable to the person it happened
/// to. Opaque keys make the second child representable; these tests are what
/// make it handled.
///
/// design/FIREBASE.md §7 rule 2 and rule 7.
final class VersionGraphTests: XCTestCase {

    private func node(_ id: String, _ parent: String?, _ time: String,
                      _ label: String? = nil) -> VersionGraph.Node {
        VersionGraph.Node(id: id, parent: parent, time: time, label: label)
    }

    /// An ordinary history: one line, no notice, latest is the end of it.
    func testALinearHistoryHasNoFork() {
        let chain = [
            node("A", nil, "2026-08-30T10:00:00-07:00", "v001"),
            node("B", "A", "2026-08-30T11:00:00-07:00", "v002"),
            node("C", "B", "2026-08-30T12:00:00-07:00", "v003"),
        ]

        XCTAssertFalse(VersionGraph.hasFork(chain))
        XCTAssertEqual(VersionGraph.latest(chain), "C")
        XCTAssertEqual(VersionGraph.lineage(of: "C", in: chain), ["A", "B", "C"])
    }

    /// Both devices' work arrives, and both are reachable.
    func testTwoDevicesAppendingToTheSameVersionBothKeepTheirWork() {
        let history = [
            node("A", nil, "2026-08-30T10:00:00-07:00", "v001"),
            node("MINE", "A", "2026-08-30T11:00:00-07:00", "v002"),
            node("THEIRS", "A", "2026-08-30T11:30:00-07:00", "v002"),
        ]

        let forks = VersionGraph.forks(history)
        XCTAssertEqual(forks.count, 1, "the split is announced once, not per version")
        XCTAssertEqual(forks.first?.parent, "A")
        XCTAssertEqual(forks.first?.children, ["THEIRS", "MINE"], "newest first")

        XCTAssertEqual(VersionGraph.latest(history), "THEIRS",
                       "latest is the most recent by timestamp")
        XCTAssertEqual(VersionGraph.siblings(of: "THEIRS", in: history), ["MINE"],
                       "and the other branch is one tap away")
    }

    /// Both children can carry the label `v002`, which is the point of the
    /// label not being the identity.
    func testForkedVersionsMayShareALabel() {
        let history = [
            node("A", nil, "2026-08-30T10:00:00-07:00", "v001"),
            node("MINE", "A", "2026-08-30T11:00:00-07:00", "v002"),
            node("THEIRS", "A", "2026-08-30T11:30:00-07:00", "v002"),
        ]

        XCTAssertEqual(Set(history.compactMap(\.label)), ["v001", "v002"])
        XCTAssertEqual(Set(history.map(\.id)).count, 3, "distinct despite the shared label")
    }

    /// Two versions made in the same second must not rank differently on two
    /// devices, or tapping an arrangement opens a different page depending on
    /// which iPad you picked up.
    func testATieIsBrokenTheSameWayEverywhere() {
        let same = "2026-08-30T11:00:00-07:00"
        let history = [
            node("A", nil, "2026-08-30T10:00:00-07:00"),
            node("AAA", "A", same),
            node("ZZZ", "A", same),
        ]

        XCTAssertEqual(VersionGraph.latest(history), "ZZZ")
        XCTAssertEqual(VersionGraph.latest(history.reversed()), "ZZZ",
                       "and the same however the documents arrived")
    }

    /// Documents arrive in whatever order the network delivers them.
    func testAChildThatLandedBeforeItsParentIsNotAFork() {
        let partial = [
            node("A", nil, "2026-08-30T10:00:00-07:00"),
            node("B", "A", "2026-08-30T11:00:00-07:00"),
            node("C", "NOT-HERE-YET", "2026-08-30T11:30:00-07:00"),
        ]

        XCTAssertFalse(VersionGraph.hasFork(partial),
                       "announcing this would train people to dismiss the notice")
        XCTAssertEqual(VersionGraph.latest(partial), "C", "and it is not lost either")
        XCTAssertEqual(VersionGraph.lineage(of: "C", in: partial), ["C"])
    }

    func testAThreeWaySplitIsOneFork() {
        let history = [
            node("A", nil, "2026-08-30T10:00:00-07:00"),
            node("X", "A", "2026-08-30T11:00:00-07:00"),
            node("Y", "A", "2026-08-30T12:00:00-07:00"),
            node("Z", "A", "2026-08-30T13:00:00-07:00"),
        ]

        let forks = VersionGraph.forks(history)
        XCTAssertEqual(forks.count, 1)
        XCTAssertEqual(forks.first?.children, ["Z", "Y", "X"])
    }

    /// A version with no time sorts last rather than crashing or winning.
    func testAVersionWithNoTimestampDoesNotBecomeLatest() {
        let history = [
            node("A", nil, "2026-08-30T10:00:00-07:00"),
            VersionGraph.Node(id: "B", parent: "A", time: nil),
        ]

        XCTAssertEqual(VersionGraph.latest(history), "A")
    }

    /// The graph is fed by the manifest the app already polls, so the manifest
    /// has to carry `parent`. It always did; nothing decoded it until now.
    func testTheManifestCarriesTheParentTheGraphNeeds() throws {
        let json = """
        {"id": "01ABC", "label": "v002", "file": "01ABC.musicxml",
         "op": "transpose", "time": "2026-08-30T11:00:00-07:00", "parent": "01AAA"}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let doc = try decoder.decode(VersionDoc.self, from: Data(json.utf8))

        XCTAssertEqual(doc.parent, "01AAA")
        XCTAssertEqual(VersionGraph.Node(doc).parent, "01AAA")
        XCTAssertEqual(VersionGraph.Node(doc).label, "v002")
    }

    /// A manifest written before this field existed still decodes.
    func testAVersionWithNoParentStillDecodes() throws {
        let json = """
        {"id": "01AAA", "file": "01AAA.musicxml", "op": "import"}
        """
        let doc = try JSONDecoder().decode(VersionDoc.self, from: Data(json.utf8))
        XCTAssertNil(doc.parent)
    }
}
