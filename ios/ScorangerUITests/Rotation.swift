import XCTest

extension XCTestCase {

    /// Rotate, and WAIT until the app agrees.
    ///
    /// `XCUIDevice.shared.orientation` is a request, not a fact: it returns
    /// immediately and the window follows some frames later. Tests that set it
    /// and measured straight afterwards were reading the OLD geometry, so a
    /// "landscape" assertion could pass having never left portrait -- observed
    /// on MixerTwoChannel, which reported a 1032x1376 window under the heading
    /// `[2ch landscape]` and asserted happily against it.
    ///
    /// That is worse than a flake: a flake fails and gets looked at, while a
    /// vacuous pass reports coverage that does not exist. So this waits on the
    /// window's own frame turning over, and FAILS if it never does rather than
    /// letting the caller measure the wrong thing.
    ///
    /// - Returns: the window frame once it matches the orientation asked for.
    /// How long to wait for a rotation, and how often to ask again.
    ///
    /// 20 seconds was enough for one simulator and not for four. Eight
    /// landscape tests failed a release gate reporting a window that had not
    /// moved a pixel -- not a frame caught mid-animation, the ORIGINAL frame --
    /// and all eight passed alone on a freshly erased device from the same
    /// build. Under four workers the request is either dropped or served
    /// later than any budget a test author measured against, which is the
    /// hazard gate.sh warns about in its own header: a wall-clock budget
    /// spent across something the host owns measures the machine.
    ///
    /// So the budget is generous and the REQUEST IS REPEATED. Nothing about
    /// what is asserted changes: the window still has to turn over, and the
    /// test still fails if it never does. A test that needs two minutes to
    /// rotate on a loaded host is telling the truth slowly; one that gives up
    /// at twenty seconds is telling a lie quickly.
    ///
    /// MEASURED, not guessed, after three wrong guesses. The same eight
    /// tests, same build, four ways:
    ///
    ///   alone on an idle device      15-25s each, all eight pass
    ///   four workers running only    22, 29, 42, 45, 49, 105, 158, 205s --
    ///     these eight tests          all eight pass
    ///   four workers + another       never rotates
    ///     worktree's four booted
    ///   the real gate, beside its    never rotates, past a 240 second budget
    ///     1357 unit tests            with the request re-issued every 8s
    ///
    /// There is no honest timeout for a starved host, so the fix is not here:
    /// every rotating test is in gate.sh's ENGINE_SERIAL and runs after the
    /// pool, one at a time, still counted and still able to fail the gate.
    ///
    /// 90 is then generous rather than hopeful -- four times the worst serial
    /// measurement, and low enough that a genuinely broken rotation costs the
    /// gate twelve minutes rather than thirty-two.
    static let rotationBudget: TimeInterval = 90
    static let rotationRetry: TimeInterval = 8

    @discardableResult
    func rotate(_ app: XCUIApplication, to orientation: UIDeviceOrientation,
                timeout: TimeInterval = XCTestCase.rotationBudget,
                file: StaticString = #filePath, line: UInt = #line) -> CGRect {
        let wantsLandscape = orientation.isLandscape
        XCUIDevice.shared.orientation = orientation
        let deadline = Date().addingTimeInterval(timeout)
        var askedAgain = Date()
        var frame = app.windows.firstMatch.frame
        while Date() < deadline {
            frame = app.windows.firstMatch.frame
            if frame.width > 0, (frame.width > frame.height) == wantsLandscape {
                // One more beat for the layout to settle after the window
                // resizes -- the frame turns over before its contents do.
                Thread.sleep(forTimeInterval: 0.6)
                return app.windows.firstMatch.frame
            }
            if Date().timeIntervalSince(askedAgain) > XCTestCase.rotationRetry {
                XCUIDevice.shared.orientation = orientation
                askedAgain = Date()
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTFail("the device never rotated to "
                + "\(wantsLandscape ? "landscape" : "portrait"): the window is "
                + "still \(frame)", file: file, line: line)
        return frame
    }
}
