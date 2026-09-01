import XCTest

/// What this device keeps, and what it must never delete (`ArtifactHolding`).
///
/// design/FIREBASE.md §5.4 asks for one of these by name: "Evicting a
/// local-only artifact is never allowed: an artifact that has not yet been
/// pushed is the only copy that exists. That check is easy to forget and is the
/// sort of thing worth a test of its own." It is the first test below.
final class ArtifactHoldingTests: XCTestCase {

    private func artifact(_ key: String,
                          bytes: Int = 500_000,
                          kind: ArtifactHolding.Kind = .notation,
                          opened: Date? = nil,
                          latest: Bool = false,
                          pinned: Bool = false,
                          offlineSetlist: Bool = false,
                          pushed: Bool = true) -> ArtifactHolding.Artifact {
        ArtifactHolding.Artifact(key: key, kind: kind, bytes: bytes,
                                 isLatest: latest, isPinned: pinned, lastOpened: opened,
                                 inOfflineSetlist: offlineSetlist, isPushed: pushed,
                                 isHeld: true)
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func daysAgo(_ n: Int) -> Date { now.addingTimeInterval(-Double(n) * 86_400) }

    // -- the one that is about loss rather than convenience ---------------

    /// An arrangement made on a plane, not yet pushed, in a library well over
    /// its budget, opened last a year ago. Every other rule says evict it.
    func testAnArtifactThatHasNotBeenPushedIsNeverEvicted() {
        let onlyCopy = artifact("plane-work", bytes: 900_000,
                                opened: daysAgo(400), pushed: false)
        let others = (1...5).map { artifact("old-\($0)", opened: daysAgo(300 + $0)) }

        let plan = ArtifactHolding.evictionPlan([onlyCopy] + others, budget: 100_000, now: now)

        XCTAssertFalse(plan.contains(onlyCopy), "this is the only copy that exists anywhere")
        XCTAssertEqual(ArtifactHolding.reasonToHold(onlyCopy, now: now), .notPushed)
    }

    /// Even when nothing else can be freed and the budget is still blown.
    func testTheBudgetLosesToAnUnpushedArtifact() {
        let onlyCopy = artifact("plane-work", bytes: 5_000_000,
                                opened: daysAgo(400), pushed: false)

        XCTAssertEqual(ArtifactHolding.evictionPlan([onlyCopy], budget: 1, now: now), [])
    }

    // -- ordinary eviction -------------------------------------------------

    /// Least recently opened first, and it stops as soon as it fits.
    func testEvictionIsLeastRecentlyOpenedAndStopsWhenItFits() {
        let artifacts = [
            artifact("a", bytes: 100, opened: daysAgo(300)),
            artifact("b", bytes: 100, opened: daysAgo(200)),
            artifact("c", bytes: 100, opened: daysAgo(100)),
        ]

        let plan = ArtifactHolding.evictionPlan(artifacts, budget: 250, now: now)

        XCTAssertEqual(plan.map(\.key), ["a"], "one is enough to get under the budget")
    }

    func testEvictionKeepsGoingUntilItFits() {
        let artifacts = (1...4).map { artifact("v\($0)", bytes: 100, opened: daysAgo(400 - $0)) }

        let plan = ArtifactHolding.evictionPlan(artifacts, budget: 150, now: now)

        XCTAssertEqual(plan.map(\.key), ["v1", "v2", "v3"])
    }

    /// The exemptions §5.4 names.
    func testASetlistMarkedOfflineAndAPinnedVersionAreExempt() {
        let artifacts = [
            artifact("gig", bytes: 1_000, opened: daysAgo(999), offlineSetlist: true),
            artifact("pinned", bytes: 1_000, opened: daysAgo(999), pinned: true),
            artifact("current", bytes: 1_000, latest: true),
            artifact("stale", bytes: 1_000, opened: daysAgo(999)),
        ]

        let plan = ArtifactHolding.evictionPlan(artifacts, budget: 1, now: now)

        XCTAssertEqual(plan.map(\.key), ["stale"],
                       "the gig, the pinned version and what opens on a tap all stay")
    }

    func testNothingIsEvictedWhenItAlreadyFits() {
        XCTAssertEqual(ArtifactHolding.evictionPlan([artifact("a", bytes: 10)],
                                                    budget: 1_000, now: now), [])
    }

    /// A version opened last month is still held; one from last year is not.
    func testRecentlyOpenedIsHeldAndThenIsNot() {
        XCTAssertEqual(ArtifactHolding.reasonToHold(artifact("recent", opened: daysAgo(3)),
                                                    now: now), .openedRecently)
        XCTAssertNil(ArtifactHolding.reasonToHold(artifact("old", opened: daysAgo(400)),
                                                  now: now))
    }

    // -- what is fetched without being asked (§5.1) ------------------------

    func testTheLatestVersionOfEveryScoreIsFetched() {
        XCTAssertTrue(ArtifactHolding.shouldFetch(artifact("current", latest: true), now: now))
    }

    func testAnOldVersionIsARowWithADownloadAffordanceNotAnError() {
        XCTAssertFalse(ArtifactHolding.shouldFetch(artifact("v003", opened: daysAgo(400)),
                                                   now: now))
    }

    /// A book is 52 MB of reference material and never arrives on a policy.
    func testABookIsNeverFetchedAutomaticallyEvenWhenItIsTheLatestThing() {
        let book = artifact("fake-book", bytes: 52_000_000, kind: .book, latest: true)

        XCTAssertFalse(ArtifactHolding.shouldFetch(book, now: now))
        XCTAssertEqual(ArtifactHolding.tier(for: book), .wifiOnly)
    }

    // -- the one setting (§5.2) --------------------------------------------

    func testDocumentsAndInkGoOverAnything() {
        XCTAssertTrue(ArtifactHolding.mayTransfer(.anyConnection, over: .cellular,
                                                  allowCellular: false))
    }

    func testNotationWaitsForWifiUnlessTheReaderSaysOtherwise() {
        let tier = ArtifactHolding.tier(for: artifact("v012"))

        XCTAssertEqual(tier, .wifiUnlessAsked)
        XCTAssertFalse(ArtifactHolding.mayTransfer(tier, over: .cellular, allowCellular: false))
        XCTAssertTrue(ArtifactHolding.mayTransfer(tier, over: .cellular, allowCellular: true))
        XCTAssertTrue(ArtifactHolding.mayTransfer(tier, over: .cellular,
                                                  allowCellular: false, asked: true),
                      "tapping download on one thing beats the setting")
    }

    /// The setting does not reach the tier that exists to stop a 52 MB
    /// download starting on a train.
    func testTheCellularSettingDoesNotUnlockABook() {
        XCTAssertFalse(ArtifactHolding.mayTransfer(.wifiOnly, over: .cellular,
                                                   allowCellular: true, asked: true))
    }

    func testALargeScanIsTreatedLikeABook() {
        let scan = artifact("big-scan", bytes: 20_000_000, kind: .pdf)
        let page = artifact("small-scan", bytes: 400_000, kind: .pdf)

        XCTAssertEqual(ArtifactHolding.tier(for: scan), .wifiOnly)
        XCTAssertEqual(ArtifactHolding.tier(for: page), .wifiUnlessAsked)
    }

    func testNothingTransfersWithNoConnection() {
        XCTAssertFalse(ArtifactHolding.mayTransfer(.anyConnection, over: .none,
                                                   allowCellular: true, asked: true))
    }
}
