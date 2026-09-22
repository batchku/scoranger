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

    /// Wait until an element's frame is one a GESTURE can be computed from.
    ///
    /// `pinch`, `swipeLeft`, `coordinate(withNormalizedOffset:)` and the rest
    /// turn the element's frame into screen points at the moment the event is
    /// synthesised. An app too busy to answer the accessibility snapshot
    /// answers with `CGRect.null` instead -- `{{inf, inf}, {0, 0}}` -- and
    /// XCTest does not check it: the arithmetic yields INFINITY and
    /// `XCPointerEventPath` raises `NSInternalInconsistencyException`, which
    /// takes the test down with a message about a parameter rather than about
    /// the app. There is nothing at the failure site to read.
    ///
    /// Seen on the 0.8.2 gate, 2026-09-16: the third of twenty back-to-back
    /// pinches in `ContinuousZoomOut`, after a snapshot the runner waited two
    /// seconds for under four workers.
    ///
    /// Returns false on timeout rather than failing, so the caller fails on
    /// its own terms -- which say what the geometry was supposed to be.
    @discardableResult
    func gesturableFrame(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        waitUntil("a frame a gesture can be computed from", timeout: timeout) {
            guard element.exists else { return false }
            let frame = element.frame
            return !frame.isNull && !frame.isInfinite && !frame.isEmpty
                && frame.origin.x.isFinite && frame.origin.y.isFinite
                && frame.size.width.isFinite && frame.size.height.isFinite
        }
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
