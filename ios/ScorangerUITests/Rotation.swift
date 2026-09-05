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
    @discardableResult
    func rotate(_ app: XCUIApplication, to orientation: UIDeviceOrientation,
                timeout: TimeInterval = 20,
                file: StaticString = #filePath, line: UInt = #line) -> CGRect {
        let wantsLandscape = orientation.isLandscape
        XCUIDevice.shared.orientation = orientation
        let deadline = Date().addingTimeInterval(timeout)
        var frame = app.windows.firstMatch.frame
        while Date() < deadline {
            frame = app.windows.firstMatch.frame
            if frame.width > 0, (frame.width > frame.height) == wantsLandscape {
                // One more beat for the layout to settle after the window
                // resizes -- the frame turns over before its contents do.
                Thread.sleep(forTimeInterval: 0.6)
                return app.windows.firstMatch.frame
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTFail("the device never rotated to "
                + "\(wantsLandscape ? "landscape" : "portrait"): the window is "
                + "still \(frame)", file: file, line: line)
        return frame
    }
}
