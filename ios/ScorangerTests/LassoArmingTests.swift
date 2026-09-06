import XCTest

/// §9.3's mode, which exists because a one-finger drag already means two
/// other things.
final class LassoArmingTests: XCTestCase {

    /// One tap arms it for a single loop, a second latches it, a third puts it
    /// away. The way out is always the control the reader's thumb is on.
    func testTheControlCyclesOffOnceLatchedOff() {
        XCTAssertEqual(LassoArming.off.tapped, .once)
        XCTAssertEqual(LassoArming.once.tapped, .latched)
        XCTAssertEqual(LassoArming.latched.tapped, .off)
    }

    /// The common case is one selection, and a mode the reader forgot they
    /// were in eats their next pan.
    func testItDisarmsAfterOneLoopUnlessLatched() {
        XCTAssertEqual(LassoArming.once.afterOneLoop, .off)
        XCTAssertEqual(LassoArming.latched.afterOneLoop, .latched)
        XCTAssertEqual(LassoArming.off.afterOneLoop, .off)
    }

    /// The two armed states behave differently on the very next gesture, so
    /// they cannot read the same.
    func testTheArmedStatesAreDistinguishable() {
        XCTAssertTrue(LassoArming.once.isArmed)
        XCTAssertTrue(LassoArming.latched.isArmed)
        XCTAssertFalse(LassoArming.off.isArmed)
        XCTAssertNotEqual(LassoArming.once.label, LassoArming.latched.label)
        XCTAssertNotEqual(LassoArming.off.label, LassoArming.once.label)
    }
}
