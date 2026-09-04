import CoreGraphics
import XCTest

/// L16 and L17: the band took half the screen whatever was in it, and its
/// version rows were bare ids.
final class TitleBandLayoutTests: XCTestCase {

    func testASmallBandIsSmall() {
        let content = TitleBandLayout.contentHeight(arrangements: 2, versions: 3,
                                                    hasAllVersionsRow: false)
        let height = TitleBandLayout.height(content: content, available: 1366)
        XCTAssertEqual(height, content, accuracy: 0.001,
                       "five rows should take five rows' worth of the screen")
        XCTAssertLessThan(height, 200)
        XCTAssertFalse(TitleBandLayout.scrolls(content: content, available: 1366))
    }

    /// A piece with many arrangements, or a long history: the band stops and
    /// scrolls rather than pushing the music off the screen.
    func testALongBandIsCappedAndScrolls() {
        let content = TitleBandLayout.contentHeight(arrangements: 40, versions: 4,
                                                    hasAllVersionsRow: true)
        let available: CGFloat = 1000
        XCTAssertEqual(TitleBandLayout.height(content: content, available: available),
                       available * TitleBandLayout.maxFraction, accuracy: 0.001)
        XCTAssertTrue(TitleBandLayout.scrolls(content: content, available: available))
    }

    func testTheCapLeavesMostOfTheScreenToTheMusic() {
        XCTAssertLessThanOrEqual(TitleBandLayout.maxFraction, 0.4)
    }

    /// The taller column decides: two arrangements beside four versions is a
    /// four-row band, not a two-row one with the versions cut off.
    func testTheTallerColumnDecides() {
        let versionsWin = TitleBandLayout.contentHeight(arrangements: 1, versions: 6,
                                                        hasAllVersionsRow: false)
        let arrangementsWin = TitleBandLayout.contentHeight(arrangements: 6, versions: 1,
                                                            hasAllVersionsRow: false)
        XCTAssertEqual(versionsWin, arrangementsWin, accuracy: 0.001)
    }

    /// An unmeasured container must not collapse the band to nothing.
    func testAnUnmeasuredContainerLeavesTheBandItsContent() {
        let content = TitleBandLayout.contentHeight(arrangements: 2, versions: 2,
                                                    hasAllVersionsRow: false)
        XCTAssertEqual(TitleBandLayout.height(content: content, available: 0),
                       content, accuracy: 0.001)
    }

    // MARK: what a version row says (L17)

    func testAVersionSaysWhatMadeIt() {
        XCTAssertEqual(TitleBandLayout.versionLabel(prompt: "make the viola an alto clef",
                                                    op: "change-clef"),
                       "make the viola an alto clef")
    }

    /// It used to say the op itself -- "transpose", "omr", "bulk-import" --
    /// which is the engine's word for it, not the reader's.
    func testWithoutAPromptItSaysWhatHappened() {
        XCTAssertEqual(TitleBandLayout.versionLabel(prompt: nil, op: "transpose"),
                       "transposed")
        XCTAssertEqual(TitleBandLayout.versionLabel(prompt: "   ", op: "transpose"),
                       "transposed")
        XCTAssertEqual(TitleBandLayout.versionLabel(prompt: nil, op: "omr"),
                       "transcribed from the scan")
    }

    func testWithNeitherItSaysSomethingRatherThanNothing() {
        XCTAssertEqual(TitleBandLayout.versionLabel(prompt: nil, op: ""), "edited")
    }
}
