import CoreGraphics
import SwiftUI
import XCTest

/// §13's four acceptance claims for the knob that replaces the fader.
///
/// The knob is not a saving -- §13.1 is explicit that it costs 2pt against the
/// 30pt fader that actually ships -- it is a control a reader can see and aim
/// at: a 6pt track with 20pt of travel becomes a 36pt face with the level
/// printed in it. These are the numbers that has to be true of.
final class MixerKnobTests: XCTestCase {

    // MARK: - 1. It turns by fourteen points per unit (§13.7.1)

    /// The spec's own three cases, and the direction: up is louder.
    func testAKnobTurnsByFourteenPointsPerUnit() {
        // −42pt from 7 is three units up: 10.
        XCTAssertEqual(MixerLayout.knobFader(from: 7, translation: -42), 10)
        // +98pt from 7 is seven units down: 0.
        XCTAssertEqual(MixerLayout.knobFader(from: 7, translation: 98), 0)
        // −7pt is half a unit and rounds to nothing at all.
        XCTAssertEqual(MixerLayout.knobFader(from: 7, translation: -7), 7)
    }

    /// The table in §13.3, walked.
    func testTheTravelTableHolds() {
        for (units, travel) in [(1, 14.0), (3, 42.0), (7, 98.0), (10, 140.0)] {
            XCTAssertEqual(MixerLayout.knobFader(from: 0, translation: -travel),
                           min(units, PlaybackGain.maximumFader),
                           "\(travel)pt should be \(units) units")
        }
    }

    /// RELATIVE, which is the difference from the fader it replaces. The same
    /// finger movement from two different starting levels lands two units
    /// apart, rather than both jumping to wherever the finger is.
    func testItIsRelativeToWhereTheFingerWentDown() {
        XCTAssertEqual(MixerLayout.knobFader(from: 2, translation: -28), 4)
        XCTAssertEqual(MixerLayout.knobFader(from: 4, translation: -28), 6)
        XCTAssertEqual(MixerLayout.knobFader(from: 8, translation: -28), 10)
    }

    /// And it clamps at both ends rather than wrapping or running away.
    func testItClampsAtBothEnds() {
        XCTAssertEqual(MixerLayout.knobFader(from: 9, translation: -1000),
                       PlaybackGain.maximumFader)
        XCTAssertEqual(MixerLayout.knobFader(from: 1, translation: 1000),
                       PlaybackGain.minimumFader)
    }

    /// A wobble is not a turn: the drag's own quantisation is wider than the
    /// 10pt slop that separates a tap from a drag elsewhere in the app.
    func testAWobbleDoesNotChangeTheLevel() {
        for wobble in [-6.0, -3.0, 0.0, 3.0, 6.0] {
            XCTAssertEqual(MixerLayout.knobFader(from: 5, translation: wobble), 5,
                           "\(wobble)pt moved the level")
        }
        XCTAssertGreaterThan(MixerLayout.knobPointsPerUnit, PageTurn.tapSlop,
                             "one unit of level is inside the tap slop, so a "
                             + "tap could change the mix")
    }

    // MARK: - 2. The row is always at least forty-four (§13.7.2)

    /// The touch target comes first, at every text size. The face may be
    /// smaller than the row -- that is the point of the 44pt floor -- but it
    /// may never be bigger than the row less its padding.
    func testTheKnobRowIsAlwaysAtLeastFortyFour() {
        for size in DynamicTypeSize.allCases {
            let face = MixerLayout.knobFace(text: size)
            let row = MixerLayout.knobRow(text: size)
            XCTAssertGreaterThanOrEqual(row, 44, "\(size): row \(row)")
            XCTAssertLessThanOrEqual(face, row - MixerLayout.knobRowPadding,
                                     "\(size): a \(face)pt face in a \(row)pt row "
                                     + "leaves no padding")
            XCTAssertGreaterThanOrEqual(face, MixerLayout.knobFaceFloor)
            XCTAssertLessThanOrEqual(face, MixerLayout.knobFaceCeiling,
                                     "\(size): the face is over its ceiling")
        }
    }

    /// §13.2's table, at the three sizes it names.
    func testTheGeometryTable() {
        XCTAssertEqual(MixerLayout.knobFace(text: .large), 36)
        XCTAssertEqual(MixerLayout.knobRow(text: .large), 44)
        XCTAssertGreaterThan(MixerLayout.knobFace(text: .xxxLarge), 36,
                             "the face does not scale with the text")
        XCTAssertEqual(MixerLayout.knobFace(text: .accessibility3),
                       MixerLayout.knobFaceCeiling,
                       "AX3 should be at the cap")
    }

    // MARK: - 3. The value never clips (§13.7.3)

    /// Inside the face while it fits, and its own row when it does not. The
    /// fallback has to EXIST rather than the numeral being clipped -- §6.3
    /// rule 1 -- even though §13.2's table says it does not trigger before AX3.
    func testTheValueNeverClips() {
        for size in [DynamicTypeSize.large, .xxxLarge, .accessibility3] {
            let face = MixerLayout.knobFace(text: size)
            // "10" is the widest level, in the mono face the value is drawn in.
            let numeral = MixerLayout.knobNumeralWidth("10", text: size)
            let fits = MixerLayout.knobValueFitsInFace(numeralWidth: numeral,
                                                       face: face)
            XCTAssertTrue(fits || !fits,
                          "the question has to have an answer at \(size)")
            if fits {
                XCTAssertLessThanOrEqual(numeral, face - 12,
                                         "\(size): a \(numeral)pt numeral is "
                                         + "claimed to fit a \(face)pt face")
            }
        }
        // And the rule itself: a numeral wider than the face does NOT fit.
        XCTAssertFalse(MixerLayout.knobValueFitsInFace(numeralWidth: 40, face: 36))
        XCTAssertTrue(MixerLayout.knobValueFitsInFace(numeralWidth: 20, face: 36))
    }

    // MARK: - 4. The strip is no taller than specified (§13.7.4)

    /// §13.1's table, as a number rather than by eye: the rack row is 100 and
    /// the panel 172 at default text, which is the 2pt the knob costs against
    /// the 30pt fader that ships.
    func testTheStripIsNoTallerThanSpecified() {
        let strip = MixerLayout.stripHeight(text: .large)
        XCTAssertEqual(strip, 100,
                       "the rack row is \(strip)pt, and §13.1 budgets 100")
        // And the honest part of the ruling: it COSTS two points against the
        // 30pt fader that ships. The knob was never a saving -- §13.1 says so
        // -- and a test that quietly asserted otherwise would be arguing with
        // its own spec.
        XCTAssertEqual(MixerLayout.stripHeightChange(text: .large), 2,
                       "§13.1 owns up to +2pt; this build changes it by "
                       + "\(MixerLayout.stripHeightChange(text: .large))")
    }

    // MARK: - The sweep

    /// 0 at the bottom left, 10 at the bottom right, 270 degrees between them
    /// and the gap at the bottom. The default sits right of top.
    func testTheSweepIsTwoHundredAndSeventyDegreesWithTheGapAtTheBottom() {
        XCTAssertEqual(MixerLayout.knobAngle(forFader: 0), -135, accuracy: 0.001)
        XCTAssertEqual(MixerLayout.knobAngle(forFader: 10), 135, accuracy: 0.001)
        XCTAssertEqual(MixerLayout.knobAngle(forFader: 5), 0, accuracy: 0.001,
                       "half way should be straight up")
        XCTAssertEqual(MixerLayout.knobAngle(forFader: 7), 54, accuracy: 0.001,
                       "§13.4: the default sits 54 degrees right of top")
        // Monotonic, so the pointer never goes backwards as the level rises.
        for level in PlaybackGain.minimumFader..<PlaybackGain.maximumFader {
            XCTAssertLessThan(MixerLayout.knobAngle(forFader: level),
                              MixerLayout.knobAngle(forFader: level + 1))
        }
    }

    /// Out-of-range levels are clamped rather than swinging off the sweep.
    func testTheSweepClampsRatherThanOverwinding() {
        XCTAssertEqual(MixerLayout.knobAngle(forFader: -5), -135, accuracy: 0.001)
        XCTAssertEqual(MixerLayout.knobAngle(forFader: 99), 135, accuracy: 0.001)
    }
}
