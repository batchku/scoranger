import XCTest

/// Does what is on screen actually FIT on it?
///
/// One form, asked of every element, against the WINDOW. That last part is
/// the whole point and it is the lesson the mixer taught twice: a panel
/// measured against its own ideal width always reports that it fits, and both
/// times the panel was drawing 60pt wider than the number it had been placed
/// by. A test that asks the layout what it intended learns nothing; a test
/// that asks the window learns what the reader is looking at.
///
/// It exists once so that §6.3's acceptance test and the tap-selection suite
/// ask the identical question. Two spellings of "is it cut off" would drift,
/// and the drift would be silent -- a screen covered by the weaker one.
extension XCTestCase {

    /// Every named element is fully inside the app's window.
    ///
    /// Missing elements are skipped rather than failed: this asks whether what
    /// IS shown fits, and a screen that does not offer a control is a
    /// different assertion belonging to a different test.
    ///
    /// `slack` is half a point, for the rounding SwiftUI does on a 3x screen.
    /// Anything larger is a real overhang -- the mixer's was 23pt and the
    /// selection chip's 1.5pt, and both were visible.
    @discardableResult
    func assertFitsOnScreen(_ identifiers: [String], in app: XCUIApplication,
                            context: String = "", slack: CGFloat = 0.5,
                            file: StaticString = #filePath,
                            line: UInt = #line) -> [String] {
        let window = app.windows.firstMatch.frame
        guard window.width > 0, window.height > 0 else {
            XCTFail("no window to measure against \(context)", file: file, line: line)
            return []
        }
        var checked: [String] = []
        for identifier in identifiers {
            let element = app.descendants(matching: .any)[identifier].firstMatch
            guard element.exists, element.frame.width > 0 else { continue }
            checked.append(identifier)
            let box = element.frame
            let where_ = context.isEmpty ? "" : " [\(context)]"
            XCTAssertLessThanOrEqual(window.minX - box.minX, slack,
                                     "\(identifier) is \(window.minX - box.minX)pt "
                                     + "off the LEFT edge\(where_): \(box) in \(window)",
                                     file: file, line: line)
            XCTAssertLessThanOrEqual(box.maxX - window.maxX, slack,
                                     "\(identifier) is \(box.maxX - window.maxX)pt "
                                     + "off the RIGHT edge\(where_): \(box) in \(window)",
                                     file: file, line: line)
            XCTAssertLessThanOrEqual(window.minY - box.minY, slack,
                                     "\(identifier) is \(window.minY - box.minY)pt "
                                     + "off the TOP\(where_): \(box) in \(window)",
                                     file: file, line: line)
            XCTAssertLessThanOrEqual(box.maxY - window.maxY, slack,
                                     "\(identifier) is \(box.maxY - window.maxY)pt "
                                     + "off the BOTTOM\(where_): \(box) in \(window)",
                                     file: file, line: line)
        }
        return checked
    }

    /// A label that has been TRUNCATED still fits the window -- it fits by
    /// giving up its own text, which is the other half of "cut off".
    ///
    /// SwiftUI truncates with U+2026, and nothing in this app's own copy ends
    /// in an ellipsis except the controls that mean "there is more here": the
    /// exceptions are named rather than guessed at.
    func assertNotTruncated(_ identifiers: [String], in app: XCUIApplication,
                            context: String = "",
                            file: StaticString = #filePath, line: UInt = #line) {
        for identifier in identifiers {
            let element = app.descendants(matching: .any)[identifier].firstMatch
            guard element.exists else { continue }
            let where_ = context.isEmpty ? "" : " [\(context)]"
            XCTAssertFalse(element.label.contains("\u{2026}"),
                           "\(identifier) is truncated\(where_): \"\(element.label)\"",
                           file: file, line: line)
        }
    }
}
