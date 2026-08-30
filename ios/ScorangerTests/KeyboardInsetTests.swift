import CoreGraphics
import XCTest

/// #59. The score screen opts out of SwiftUI's automatic keyboard avoidance, so
/// the panels that own a text field have to lift themselves.
final class KeyboardInsetTests: XCTestCase {
    func testNoKeyboardLiftsNothing() {
        XCTAssertEqual(KeyboardInset.panelBottom(keyboard: 0, safeAreaBottom: 20), 0)
    }

    /// The panel already sits clear of the home indicator, so it needs the rest
    /// of the keyboard and not all of it -- adding the whole height would leave
    /// a 20pt band of dead space under the input.
    func testAPanelIsLiftedByWhatTheKeyboardCoversAboveTheSafeArea() {
        XCTAssertEqual(KeyboardInset.panelBottom(keyboard: 380, safeAreaBottom: 20), 360)
    }

    func testAKeyboardShorterThanTheSafeAreaNeverPushesAPanelDown() {
        XCTAssertEqual(KeyboardInset.panelBottom(keyboard: 10, safeAreaBottom: 20), 0)
    }

    func testAScreenWithNoHomeIndicatorTakesTheWholeKeyboard() {
        XCTAssertEqual(KeyboardInset.panelBottom(keyboard: 336, safeAreaBottom: 0), 336)
    }
}
