import Foundation
import XCTest

/// Verovio's `setOptions` merges: it sets what the JSON names and leaves the
/// rest alone. An option named in one layout's set and omitted from the other's
/// is therefore not a default -- it is a value the first layout leaves behind
/// for the second to find, and the toolkit is shared and long-lived.
///
/// The paged set used not to name `breaks`. One visit to continuous mode set it
/// to "none", and every paged engrave afterwards drew the whole score as one
/// system on one page: no pagination, "p. 1 / 1", a blurred raster and garbled
/// thumbnails, all from that.
final class EngravingOptionsTests: XCTestCase {

    private func value(_ key: String, in json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any],
              let found = dict[key] else { return nil }
        return String(describing: found)
    }

    /// The whole point: both sets name every option that differs between them.
    func testEveryLayoutDependentOptionIsNamedInBothSets() {
        for continuous in [false, true] {
            let json = EngravingOptions.json(lyricSize: 4.5, continuous: continuous)
            for key in EngravingOptions.layoutDependentKeys {
                XCTAssertNotNil(value(key, in: json),
                                "\(key) is missing from the \(continuous ? "continuous" : "paged") "
                                + "option set, so the other layout's value survives into it")
            }
        }
    }

    func testBothSetsAreValidJSON() {
        for continuous in [false, true] {
            let json = EngravingOptions.json(lyricSize: 4.5, continuous: continuous)
            let data = Data(json.utf8)
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data),
                             "the \(continuous ? "continuous" : "paged") options are not JSON")
        }
    }

    /// Paged breaks pages; continuous refuses to.
    func testBreaksDifferByLayout() {
        XCTAssertEqual(EngravingOptions.breaks(continuous: false), "auto")
        XCTAssertEqual(EngravingOptions.breaks(continuous: true), "none")
        XCTAssertEqual(value("breaks", in: EngravingOptions.json(lyricSize: 4.5,
                                                                continuous: false)), "auto")
        XCTAssertEqual(value("breaks", in: EngravingOptions.json(lyricSize: 4.5,
                                                                continuous: true)), "none")
    }

    /// A page keeps its paper height; the strip is trimmed to its one system.
    func testPageHeightIsOnlyAdjustedForTheStrip() {
        XCTAssertFalse(EngravingOptions.adjustPageHeight(continuous: false))
        XCTAssertTrue(EngravingOptions.adjustPageHeight(continuous: true))
    }

    /// The page size the canvas measures. Verovio emits `tenths * scale/100`
    /// points, and reports 972 x 1258 for these options.
    func testEngravedPageSizeMatchesWhatVerovioEmits() {
        XCTAssertEqual(EngravingOptions.pageSize.width, 971.55, accuracy: 0.5)
        XCTAssertEqual(EngravingOptions.pageSize.height, 1257.3, accuracy: 0.5)
    }
}
