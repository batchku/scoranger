import XCTest

/// The score's own spacing, read out of its notation.
///
/// `ops.staff_spacing` writes it and `render.spacing_from_musicxml` reads it on
/// the export side; engine/scripts/check_staff_spacing.py holds this file's
/// constants to the engine's. What is asserted here is the parse and the
/// option set, which are the parts only Swift can get wrong.
final class StaffSpacingTests: XCTestCase {

    private func xml(_ field: String) -> String {
        "<identification><miscellaneous><miscellaneous-field name=\"scoranger-spacing\">"
            + field + "</miscellaneous-field></miscellaneous></identification>"
    }

    /// A score nobody has spaced is laid out exactly as before, except for the
    /// fingering band, whose default is the fix.
    func testAScoreWithNoFieldGetsTheDefaults() {
        let values = StaffSpacing.values(inMusicXML: "<score-partwise/>")
        XCTAssertEqual(values, StaffSpacing.defaults)
        XCTAssertEqual(values.staff, 12, "Verovio's own spacingStaff")
        XCTAssertEqual(values.system, 4, "Verovio's own spacingSystem")
        XCTAssertEqual(values.rows, 4, "four rows: the tightest the column fits inside its band")
    }

    func testTheFieldIsRead() {
        let values = StaffSpacing.values(inMusicXML: xml("staff=20;system=10;rows=5"))
        XCTAssertEqual(values, StaffSpacing.Values(staff: 20, system: 10, rows: 5))
    }

    /// Only what the field names changes: the op writes only what differs
    /// from a default.
    func testAPartialFieldKeepsTheOtherDefaults() {
        let values = StaffSpacing.values(inMusicXML: xml("rows=6"))
        XCTAssertEqual(values, StaffSpacing.Values(staff: 12, system: 4, rows: 6))
    }

    /// Lenient on the way in: a value out of range, unreadable or unknown falls
    /// back to its default rather than stopping a page from drawing. The op is
    /// the strict side, and refuses these by name before they are ever written.
    func testABadValueFallsBackRatherThanBreakingThePage() {
        let values = StaffSpacing.values(inMusicXML: xml("staff=99;system=x;rows=2;colour=blue"))
        XCTAssertEqual(values, StaffSpacing.defaults)
    }

    /// Both spacing keys are named in EVERY option set, defaults included: the
    /// toolkit is shared and `setOptions` merges, so one score's wide staves
    /// would otherwise be the next score's.
    func testEveryOptionSetNamesTheSpacing() {
        for continuous in [false, true] {
            let json = EngravingOptions.json(lyricSize: 4.5, continuous: continuous)
            for key in EngravingOptions.scoreDependentKeys {
                XCTAssertTrue(json.contains("\"\(key)\""),
                              "\(key) missing from the \(continuous ? "continuous" : "paged") set")
            }
        }
        let wide = EngravingOptions.json(lyricSize: 4.5, continuous: false,
                                         spacing: StaffSpacing.Values(staff: 30, system: 20, rows: 3))
        XCTAssertTrue(wide.contains("\"spacingStaff\": 30"))
        XCTAssertTrue(wide.contains("\"spacingSystem\": 20"))
    }

    /// The step line the reader watches. Providers send numbers and flags as
    /// JSON values, not strings, so both spellings have to read.
    func testTheStepSaysWhatTheSpacingIsDoing() {
        XCTAssertEqual(ChatSteps.stepTitle(name: "staff_spacing", argsJSON: #"{"fingering_rows": 4}"#),
                       "Giving the fingerings 4 rows")
        XCTAssertEqual(ChatSteps.stepTitle(name: "staff_spacing", argsJSON: #"{"reset": true}"#),
                       "Putting the spacing back")
        XCTAssertEqual(ChatSteps.stepTitle(name: "staff_spacing", argsJSON: #"{"staff": 20}"#),
                       "Respacing the staves")
        XCTAssertEqual(ChatSteps.stepTitle(name: "paginate", argsJSON: #"{"measures_per_line": 4}"#),
                       "Laying it out 4 bars to a line")
        XCTAssertEqual(ChatSteps.stepTitle(name: "paginate", argsJSON: #"{"clear": true}"#),
                       "Letting the engraver lay it out")
    }
}
