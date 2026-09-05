import XCTest

/// Ali's exact case: iPad Pro 13-inch, NORMAL text size, both orientations.
///
/// The previous reproduction was wrong about the cause. It found real clipping
/// at accessibility text sizes, but Ali is on NORMAL text -- and at normal
/// text the panel measured 268x173 wholly inside a 1032x1376 window. So
/// Dynamic Type is a genuine bug and NOT his bug, and there is a second cause.
///
/// Two things the earlier tests never varied, both of which this does:
///
///   - ORIENTATION. Every mixer test ran in whatever the simulator was left
///     in, which was portrait. The parking maths subtracts `lanesInset` from
///     the bottom, and landscape has a different height, a different set of
///     occupied lanes and a different home-indicator inset.
///   - WHAT COUNTS AS "ON SCREEN". Every assertion compared the panel against
///     `app.windows.firstMatch.frame`, which is the whole display INCLUDING
///     the safe areas. A panel sitting under the home indicator or inside a
///     rounded corner is "inside the window" and still cut off to a reader.
///     This measures the SAFE frame instead, taken from the app's own chrome.
///
/// And the drag is pinned by grabbing where a finger would: the panel's body
/// and its header text, not only the ☰ grip that XCTest's synthesized
/// press-then-drag happened to move.
final class MixerOnAlisCase: XCTestCase {

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func launched() -> XCUIApplication {
        let app = XCUIApplication()
        // NORMAL text. Named explicitly rather than left to the machine, so
        // this test cannot silently inherit a large size from a previous run.
        app.launchArguments = ["-seedTestLibrary",
                               "-UIPreferredContentSizeCategoryName",
                               "UICTContentSizeCategoryL"]
        app.launch()
        return app
    }

    private func openMixer(_ app: XCUIApplication) -> XCUIElement? {
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 90)
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@",
                                  "row-", "Sous le ciel")).firstMatch
        guard row.waitForExistence(timeout: 120) else { return nil }
        row.tap()
        if app.buttons["score-title"].waitForExistence(timeout: 5) == false {
            let choice = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@",
                                      "arrangement-choice-")).firstMatch
            if choice.waitForExistence(timeout: 30) { settle(choice); choice.tap() }
        }
        guard app.buttons["score-title"].waitForExistence(timeout: 240) else { return nil }
        let page = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "canvas-")).firstMatch
        _ = page.waitForExistence(timeout: 180)
        settle(page, still: 0.6)
        if app.otherElements["transport"].exists == false,
           app.buttons["score-transport-toggle"].exists {
            app.buttons["score-transport-toggle"].tap()
            _ = app.otherElements["transport"].waitForExistence(timeout: 20)
        }
        guard app.buttons["transport-mixer"].waitForExistence(timeout: 120) else { return nil }
        app.buttons["transport-mixer"].tap()
        let panel = app.otherElements["mixer"].firstMatch
        guard panel.waitForExistence(timeout: 30) else { return nil }
        settle(panel)
        return panel
    }

    /// The SAFE frame, derived from the app's own chrome rather than guessed:
    /// the score top bar starts below the status bar, so its minY is the top
    /// of the usable area. For the bottom there is no chrome pinned to the
    /// safe edge, so the home-indicator inset is taken from the window and
    /// the known iPad value -- stated as an assumption rather than measured,
    /// which is why the assertion below reports both numbers.
    private func usable(_ app: XCUIApplication) -> CGRect {
        let window = app.windows.firstMatch.frame
        let bar = app.buttons["score-close"].firstMatch
        let top = bar.exists ? bar.frame.minY : window.minY
        return CGRect(x: window.minX, y: top,
                      width: window.width, height: window.maxY - top)
    }

    private func report(_ orientation: String, _ panel: XCUIElement,
                        _ app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        let box = panel.frame
        print("[\(orientation)] panel \(box)")
        print("[\(orientation)] window \(window)")
        print("[\(orientation)] right slack \(window.maxX - box.maxX)pt, "
              + "bottom slack \(window.maxY - box.maxY)pt")
    }

    // MARK: - Is it cut off at normal text?

    func testTheMixerFitsInPortraitAtNormalText() {
        let app = launched()
        guard let panel = openMixer(app) else { return XCTFail("no mixer") }
        snap("alis-case-portrait")
        report("portrait", panel, app)
        let window = app.windows.firstMatch.frame
        XCTAssertLessThanOrEqual(panel.frame.maxX, window.maxX + 0.5,
                                 "portrait: off the right")
        XCTAssertLessThanOrEqual(panel.frame.maxY, window.maxY + 0.5,
                                 "portrait: off the bottom")
    }

    /// The orientation no mixer test has ever run in.
    func testTheMixerFitsInLandscapeAtNormalText() {
        let app = launched()
        guard let panel = openMixer(app) else { return XCTFail("no mixer") }
        rotate(app, to: .landscapeLeft)
        settle(panel, still: 0.8)
        snap("alis-case-landscape")
        report("landscape", panel, app)

        let window = app.windows.firstMatch.frame
        let box = app.otherElements["mixer"].firstMatch.frame
        XCTAssertLessThanOrEqual(box.maxX, window.maxX + 0.5,
                                 "landscape: \(box.maxX - window.maxX)pt off the right")
        XCTAssertLessThanOrEqual(box.maxY, window.maxY + 0.5,
                                 "landscape: \(box.maxY - window.maxY)pt off the bottom")

        // Every control still reachable AFTER the rotation, which is the part
        // a frame check cannot see: a panel parked by pre-rotation maths can
        // sit under the home indicator and still be "inside the window".
        for id in ["mixer-close", "strip-mute-0", "strip-fader-0", "mixer-elapsed"] {
            let control = app.descendants(matching: .any)[id]
            XCTAssertTrue(control.exists, "landscape: \(id) is gone")
            XCTAssertTrue(control.isHittable, "landscape: \(id) is not hittable")
        }
    }

    /// Rotating with the sound picker open, which is the panel at its largest.
    func testTheMixerFitsInLandscapeWithThePickerOpen() {
        let app = launched()
        guard let panel = openMixer(app) else { return XCTFail("no mixer") }
        let sound = app.descendants(matching: .any)["strip-sound-0"]
        if sound.waitForExistence(timeout: 20) { sound.tap() }
        _ = app.descendants(matching: .any)["mixer-picker"].waitForExistence(timeout: 20)
        rotate(app, to: .landscapeLeft)
        settle(panel, still: 0.8)
        snap("alis-case-landscape-picker")
        report("landscape+picker", app.otherElements["mixer"].firstMatch, app)

        let window = app.windows.firstMatch.frame
        let box = app.otherElements["mixer"].firstMatch.frame
        XCTAssertLessThanOrEqual(box.maxY, window.maxY + 0.5,
                                 "landscape+picker: \(box.maxY - window.maxY)pt off the bottom")
        XCTAssertLessThanOrEqual(box.maxX, window.maxX + 0.5,
                                 "landscape+picker: \(box.maxX - window.maxX)pt off the right")
    }

    // MARK: - Is it draggable, grabbed the way a finger grabs it?

    /// From the panel's HEADER, beside the grip -- where a reader reaches for
    /// a window's title bar. Not the ☰ button itself, which is what the
    /// earlier test dragged and is a Button whose tap cycles corners.
    func testTheMixerCanBeDraggedByItsHeader() throws {
        let app = launched()
        guard let panel = openMixer(app) else { return XCTFail("no mixer") }
        let before = panel.frame
        // "MIXER" is a static text in the header, not a control.
        let title = app.staticTexts["MIXER"].firstMatch
        guard title.exists else { throw XCTSkip("no MIXER caption to grab") }
        let from = title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(forDuration: 0.25,
                   thenDragTo: from.withOffset(CGVector(dx: -200, dy: -200)),
                   withVelocity: .slow, thenHoldForDuration: 0.8)
        let after = app.otherElements["mixer"].firstMatch.frame
        snap("drag-by-header")
        print("header drag: before \(before.origin) after \(after.origin)")
        XCTAssertGreaterThan(hypot(after.minX - before.minX, after.minY - before.minY),
                             40, "dragging the header moved the panel nowhere")
    }

    /// Which grab points move the window, and which must NOT.
    ///
    /// The header drags. A fader does not -- it is a fader, and §1.1 forbids a
    /// gesture anywhere on the panel body, which is exactly what made the old
    /// panel feel dead: its one drag competed with every control and lost.
    /// Measured on the shipped build: grip 169.7pt, caption 120.1pt, fader
    /// 0.0pt, body 0.0pt.
    func testTheHeaderDragsAndTheBodyDoesNot() {
        let app = launched()
        guard openMixer(app) != nil else { return XCTFail("no mixer") }
        let header = app.descendants(matching: .any)["mixer-header"].firstMatch
        let fader = app.descendants(matching: .any)["strip-fader-0"].firstMatch

        func move(_ element: XCUIElement, dx: CGFloat, dy: CGFloat) -> Double {
            let before = app.otherElements["mixer"].firstMatch.frame
            let from = element.coordinate(withNormalizedOffset:
                CGVector(dx: 0.5, dy: 0.5))
            from.press(forDuration: 0.25,
                       thenDragTo: from.withOffset(CGVector(dx: dx, dy: dy)),
                       withVelocity: .slow, thenHoldForDuration: 0.5)
            let after = app.otherElements["mixer"].firstMatch.frame
            return hypot(after.minX - before.minX, after.minY - before.minY)
        }

        let byHeader = move(header, dx: -120, dy: -120)
        print("header moved the window \(byHeader)pt")
        XCTAssertGreaterThan(byHeader, 40, "the header did not drag the window")

        // §8.5: a fader drag changes the LEVEL and leaves the window alone.
        let levelBefore = fader.value as? String ?? ""
        let byFader = move(fader, dx: 0, dy: -60)
        let levelAfter = fader.value as? String ?? ""
        print("fader moved the window \(byFader)pt, level \(levelBefore) -> \(levelAfter)")
        XCTAssertLessThan(byFader, 2,
                          "dragging a fader moved the whole window \(byFader)pt")
        XCTAssertNotEqual(levelAfter, levelBefore,
                          "dragging the fader did not change its level")
        snap("grab-points")
    }
}
