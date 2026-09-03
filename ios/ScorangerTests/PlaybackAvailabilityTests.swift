import XCTest

/// Why the transport cannot play, and what the reader can do about it.
///
/// The bug these pin was reported as "does build 160 even have playback?". It
/// did. The reader's library is 44 imported PDFs, every one a scan, and a scan
/// has no notation to play -- so the transport correctly replaced its buttons
/// with the sentence "Run OMR to play this arrangement" on every score he
/// owned. Accurate, and a dead end: it named the remedy and did not offer it.
final class PlaybackAvailabilityTests: XCTestCase {

    /// The case the whole change exists for: a scan offers the fix.
    func testAScanOffersTheThingThatWouldFixIt() {
        let state = PlaybackAvailability.needsTranscription

        XCTAssertFalse(state.canPlay)
        XCTAssertEqual(state.actionTitle, "Run OMR to play")
    }

    /// The remote engine is fixable too, in Settings rather than here.
    func testTheRemoteEngineAlsoPointsSomewhere() {
        XCTAssertEqual(PlaybackAvailability.needsLocalEngine.actionTitle, "Open Settings")
    }

    /// Every reason a reader can act on must carry its action. A reason that
    /// cannot be acted on is fine; a reason that CAN and does not is the bug.
    func testNoActionableReasonIsLeftWithoutAButton() {
        for state in [PlaybackAvailability.needsTranscription, .needsLocalEngine] {
            XCTAssertNotNil(state.actionTitle, "\(state) names no remedy")
            XCTAssertFalse(state.message.isEmpty, "\(state) says nothing")
        }
    }

    /// While it runs there is nothing to press -- pressing again would start a
    /// second transcription of the same page.
    func testThereIsNothingToPressWhileItIsRunning() {
        XCTAssertNil(PlaybackAvailability.transcribing.actionTitle)
        XCTAssertFalse(PlaybackAvailability.transcribing.canPlay)
    }

    /// OMR on a dense or oversized page is imperfect by nature. A reader told
    /// AFTERWARDS that their notation is a draft has already been misled once,
    /// so the warning is on the offer as well as on the wait.
    func testTheDraftIsAdmittedBeforeTheWaitAndDuringIt() {
        XCTAssertTrue(PlaybackAvailability.needsTranscription.warnsItIsADraft)
        XCTAssertTrue(PlaybackAvailability.transcribing.warnsItIsADraft)
        XCTAssertTrue(PlaybackAvailability.transcribing.message.contains("draft"))
    }

    /// Playing says nothing and offers nothing: the buttons are there instead.
    func testWhenItCanPlayTheTransportSaysNothingAtAll() {
        XCTAssertTrue(PlaybackAvailability.available.canPlay)
        XCTAssertEqual(PlaybackAvailability.available.message, "")
        XCTAssertNil(PlaybackAvailability.available.actionTitle)
    }

    /// Each state is separately addressable, so a test can tell which one is
    /// on screen rather than matching prose.
    func testEachStateIsIdentifiable() {
        let all: [PlaybackAvailability] = [.available, .needsTranscription,
                                           .transcribing, .needsLocalEngine]
        XCTAssertEqual(Set(all.map(\.identifier)).count, all.count)
    }
}

/// The rule itself, which is what makes the transport come back on its own.
extension PlaybackAvailabilityTests {

    /// The sequence a reader actually lives through: a scan offers OMR, OMR
    /// runs, and when it lands the arrangement PLAYS -- with no reopening.
    /// The answer is derived from what is on screen, so the transport cannot
    /// be left holding a stale reason.
    func testAfterTranscriptionTheTransportPlaysWithoutBeingReopened() {
        let before = PlaybackAvailability.of(artifact: .scan, omrBusy: false, localEngine: true)
        let during = PlaybackAvailability.of(artifact: .scan, omrBusy: true, localEngine: true)
        // OMR adds a NOTATION version, and the view follows the newest one
        let after = PlaybackAvailability.of(artifact: .notation, omrBusy: false, localEngine: true)

        XCTAssertEqual(before, .needsTranscription)
        XCTAssertEqual(during, .transcribing)
        XCTAssertEqual(after, .available, "the reader would have to reopen the score")
    }

    /// A second tap while it runs would start a second transcription of the
    /// same page, so the offer is withdrawn for the duration.
    func testTheOfferIsWithdrawnWhileItRuns() {
        XCTAssertNil(PlaybackAvailability
            .of(artifact: .scan, omrBusy: true, localEngine: true).actionTitle)
    }

    /// Notation on the remote engine is the other unplayable case, and it is
    /// NOT confused with a scan -- the remedies are different places.
    func testNotationOnTheRemoteEngineIsADifferentProblem() {
        XCTAssertEqual(PlaybackAvailability
            .of(artifact: .notation, omrBusy: false, localEngine: false), .needsLocalEngine)
    }

    /// A scan on the remote engine is still a scan: transcribe first.
    func testAScanIsAScanWhicheverEngineIsRunning() {
        XCTAssertEqual(PlaybackAvailability
            .of(artifact: .scan, omrBusy: false, localEngine: false), .needsTranscription)
    }
}
