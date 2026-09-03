import XCTest

/// Waiting for the thing, rather than for a number of seconds.
///
/// The suite had eighty-seven unconditional `sleep`s in it, about six minutes
/// of the gate. Each one was a guess at how long something takes on an idle
/// machine, and every guess is wrong in both directions at once: too long on
/// the run where the animation finished immediately, too short on the run
/// where it did not. Four simulators testing at the same time is not an idle
/// machine, so the too-short end stopped being theoretical -- a `sleep(1)`
/// after opening a panel is a coin toss under load, and a test that fails that
/// way looks like a flake rather than like a missing wait.
///
/// These are the two waits the suite actually needs. `waitUntil` for a fact
/// that becomes true; `settle` for a frame that stops moving, which is what
/// nearly every one of those sleeps was standing in for -- the assertion after
/// it measures a geometry, and SwiftUI is still animating it.
extension XCTestCase {

    /// Poll until the condition holds. Returns whether it did.
    @discardableResult
    func waitUntil(_ what: String, timeout: TimeInterval = 30,
                   poll: TimeInterval = 0.12,
                   _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(useconds_t(poll * 1_000_000))
        }
        return condition()
    }

    /// Poll until the condition holds, and fail the test if it never does.
    @discardableResult
    func expect(_ what: String, timeout: TimeInterval = 30,
                file: StaticString = #filePath, line: UInt = #line,
                _ condition: () -> Bool) -> Bool {
        let ok = waitUntil(what, timeout: timeout, condition)
        if !ok { XCTFail("timed out waiting for \(what)", file: file, line: line) }
        return ok
    }

    /// Wait until an element's frame has held still for a beat.
    ///
    /// Returns false on timeout rather than failing: several callers only want
    /// the layout to stop moving before they measure it, and a slow machine
    /// that never quite settles should fail on the measurement -- which says
    /// what was wrong with the geometry -- not here.
    @discardableResult
    func settle(_ element: XCUIElement, still: TimeInterval = 0.35,
                timeout: TimeInterval = 20) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var last = element.exists ? element.frame : .zero
        var unchangedSince = Date()
        while Date() < deadline {
            usleep(100_000)
            let now = element.exists ? element.frame : .zero
            if now == last {
                if Date().timeIntervalSince(unchangedSince) >= still { return true }
            } else {
                last = now
                unchangedSince = Date()
            }
        }
        return false
    }

    /// Both frames still. Two panels open together and the second one moves
    /// the first, so waiting on one of them alone can return between the two.
    ///
    /// Labelled `all:` rather than overloading the name: `XCTestCase` is an
    /// Objective-C class, and two Swift overloads that differ only in the type
    /// of their first argument compile to the same selector.
    @discardableResult
    func settle(all elements: [XCUIElement], still: TimeInterval = 0.35,
                timeout: TimeInterval = 20) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var last = elements.map { $0.exists ? $0.frame : .zero }
        var unchangedSince = Date()
        while Date() < deadline {
            usleep(100_000)
            let now = elements.map { $0.exists ? $0.frame : .zero }
            if now == last {
                if Date().timeIntervalSince(unchangedSince) >= still { return true }
            } else {
                last = now
                unchangedSince = Date()
            }
        }
        return false
    }
}
