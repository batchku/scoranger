import XCTest

/// Pagination survives an op that ADDS material to the score.
///
/// Ali: after a chat op that changes the score -- adding a staff, a tab,
/// chords -- "the layout collapses to one long squished illegible system".
///
/// "One long squished system" is exactly what `breaks: "none"` produces, and
/// that was the obvious suspect: `VerovioRenderer` keeps ONE toolkit,
/// Verovio's `setOptions` MERGES, and a continuous engrave leaking its
/// `breaks` into every paged one afterwards is a fault this app has had and
/// fixed once (`EngravingOptions`). It is NOT this one. Replaying the whole
/// sequence against the same Verovio with the iOS option sets verbatim --
/// paged, paged with an MEI reload, a continuous visit, paged again -- gives
/// 9 pages every single time. The engine's own renderer paginates through an
/// op too: 8 pages before a tab, 12 after, which is a tab adding height and
/// not a collapse.
///
/// What is left is the part Python never exercises: the SWIFT MEI transforms
/// in `engrave` -- `FingeringDiagrams.meiWithFingeringsAbove`,
/// `ChordPlacement.meiWithChartStyling`, `ChordAdjustments`,
/// `ChordDiagrams.meiWithDiagrams`, `RehearsalMarks`. Each rewrites the MEI
/// as text and sets `reload`, and the document is then re-read from what they
/// produced. Ali's three examples are exactly the three that trigger them,
/// and a score with none of them never takes that path -- which is why every
/// pagination test in this suite has passed.
///
/// So the fixtures here are scores that HAVE those elements, seeded through
/// the real engine rather than from a canned file, and the assertion is the
/// page counter the existing pagination guard already uses.
final class PaginationAfterAnOp: XCTestCase {

    private var app: XCUIApplication!

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// A plain wait, alongside the shared element-based `settle`. RenderShot
    /// carries the same private helper for the same reason: waiting on a page
    /// COUNT is waiting on a number, not on an element appearing.
    private func settle(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// "pages=8 systems=3,3,3,4,3,3,3,3" -- the per-page SYSTEM count, under
    /// `-geometryProbe`. The page count alone cannot tell a collapse from a
    /// short piece; the system count can.
    private var probe: String {
        let element = app.descendants(matching: .any)["geometry-probe"]
        return element.exists ? element.label : ""
    }

    private func systems(in probe: String) -> [Int] {
        guard let part = probe.split(separator: " ")
            .first(where: { $0.hasPrefix("systems=") })?
            .dropFirst("systems=".count) else { return [] }
        return part.split(separator: ",").compactMap { Int($0) }
    }

    private func waitForProbe(timeout: TimeInterval = 120) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let now = probe
            if !systems(in: now).isEmpty { settle(0.8); return probe }
            settle(0.5)
        }
        return probe
    }

    private var counter: String {
        let chip = app.staticTexts["counter-pages"]
        return chip.exists ? chip.label : ""
    }

    /// The total in "p. 3 / 9", or 0 when the counter is absent.
    private func pages(in label: String) -> Int {
        guard let slash = label.lastIndex(of: "/") else { return 0 }
        return Int(label[label.index(after: slash)...]
            .trimmingCharacters(in: .whitespaces)) ?? 0
    }

    private func waitForPages(_ want: (Int) -> Bool,
                              timeout: TimeInterval = 120) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if want(pages(in: counter)) { settle(0.8); return counter }
            settle(0.5)
        }
        return counter
    }

    /// Open the score the seed put the fixture on: the first by slug, which is
    /// what both seed flags target.
    private func openTheFixture() -> Bool {
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 240)
        let row = app.descendants(matching: .any)["row-sous-le-ciel-de-paris"]
        guard row.waitForExistence(timeout: 180) else { return false }
        row.tap()
        // THE ACCORDION SOLO, not the quartet. Ali's score is a folk tune on
        // two staves, and on a score that short "p. 1 / 1" may be CORRECT --
        // the music fits. The quartet is 4 staves and 136 bars and would
        // paginate no matter what, so it cannot show his fault.
        let choice = app.descendants(matching: .any)[
            "arrangement-choice-under-paris-skies-accordion-solo"]
        if choice.waitForExistence(timeout: 60) { settle(choice); choice.tap() }
        guard app.buttons["score-title"].waitForExistence(timeout: 300) else { return false }
        let page = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "canvas-")).firstMatch
        _ = page.waitForExistence(timeout: 240)
        settle(page, still: 0.8)
        return true
    }

    /// The score paginates when it carries CHORD SYMBOLS, which is the
    /// `ChordPlacement` transform's reload path.
    func testPaginationSurvivesChordSymbols() {
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-seedTestLibrary", "-seedChordChart"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        guard openTheFixture() else { return XCTFail("the fixture never opened") }
        let seen = waitForPages { $0 > 0 }
        snap("pagination-with-chord-symbols")
        print("PAGINATION chords: counter = \"\(seen)\"")
        XCTAssertGreaterThan(pages(in: seen), 1,
                             "a score carrying chord symbols engraved to "
                             + "\(pages(in: seen)) page(s): \"\(seen)\"")
    }

    /// And when it carries a GUITAR TAB, which is the `FingeringDiagrams`
    /// reload path -- lyric verses moved above the staff on the MEI.
    func testPaginationSurvivesAGuitarTab() {
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-seedTestLibrary", "-seedGuitarTab"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        guard openTheFixture() else { return XCTFail("the fixture never opened") }
        let seen = waitForPages { $0 > 0 }
        snap("pagination-with-a-guitar-tab")
        print("PAGINATION tab: counter = \"\(seen)\"")
        XCTAssertGreaterThan(pages(in: seen), 1,
                             "a score carrying a guitar tab engraved to "
                             + "\(pages(in: seen)) page(s): \"\(seen)\"")
    }

    /// The control, and the reason the two above mean anything: the SAME
    /// score with none of those elements. If this one also came back as a
    /// single page the fixture would be wrong, not the transforms.
    func testTheSameScoreWithoutThemPaginates() {
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-seedTestLibrary"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        guard openTheFixture() else { return XCTFail("the fixture never opened") }
        let seen = waitForPages { $0 > 0 }
        print("PAGINATION control: counter = \"\(seen)\"")
        XCTAssertGreaterThan(pages(in: seen), 1,
                             "the control score is \(pages(in: seen)) page(s), "
                             + "so the fixture is wrong rather than the transforms")
    }

    /// Ali's prompt, as one score: a second staff, then a tab on it, then
    /// chords, then diagrams over the chords.
    ///
    /// The three fixtures above each paginate on their own -- 9 pages plain,
    /// 8 with chords, 11 with a tab -- so a collapse here is the COMBINATION,
    /// and the added staff is the input none of them had. His screenshot read
    /// "p. 1 / 1" with the fingering row crammed and overlapping, which is
    /// what a system that no longer fits its page looks like.
    func testPaginationSurvivesAddingAStaffThenTabThenChords() {
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-seedTestLibrary", "-seedCombinedOp"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        guard openTheFixture() else { return XCTFail("the fixture never opened") }
        let seen = waitForPages { $0 > 0 }
        snap("pagination-after-the-combined-op")
        print("PAGINATION combined: counter = \"\(seen)\"")
        XCTAssertGreaterThan(pages(in: seen), 1,
                             "after a staff, a tab, chords and diagrams the "
                             + "score engraved to \(pages(in: seen)) page(s): "
                             + "\"\(seen)\" -- which is Ali's p. 1 / 1")
    }

    // MARK: - The observable, validated

    /// The Swift system count must agree with the engine's, or every number
    /// below it is a number about the inference rather than about the score.
    ///
    /// The engine renders the same file with the same Verovio and counts
    /// `class="system"` in the SVG directly. On the accordion solo as
    /// imported it reports 5 pages and 25 systems, [5, 6, 6, 5, 3]. The app
    /// infers systems from bar frames, which is a different method on the
    /// same drawing -- so agreement is evidence, and disagreement would mean
    /// the observable is broken before it has said anything about #4.
    func testTheSystemCountAgreesWithTheEngine() {
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-seedTestLibrary", "-geometryProbe"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        guard openTheFixture() else { return XCTFail("the fixture never opened") }
        let seen = waitForProbe()
        print("PROBE as-imported: \(seen)  counter=\"\(counter)\"")
        // The TOTAL, not the distribution. The engine renders with
        // render.py's page setup and the app with EngravingOptions', so the
        // same 25 systems fall 5-6 to a page there and 2-3 here -- comparing
        // per-page asserted a difference that is not a fault. What has to
        // agree is how many lines the music is broken into, which is the
        // thing the two methods both measure and the thing #4 is about.
        XCTAssertEqual(systems(in: seen).reduce(0, +), 25,
                       "the app and the engine disagree about how many systems "
                       + "this file has: app \(seen), engine 25")
    }

    /// And #4 itself: the combined op, through the iOS engrave path.
    ///
    /// Ali's prompt in one version -- a second staff, a tab on it, chords,
    /// diagrams -- on a two-staff folk tune, in PAGE view. His screenshot is
    /// one long system and "p. 1 / 1". The engine does not reproduce it: 25
    /// systems at every step of the same sequence, pages growing 5 -> 8 -> 9
    /// as the added material makes systems taller.
    ///
    /// THE CONTROL IS THE PRECONDITION, and two weaker ones failed first. A
    /// bare "did it collapse" passed on geometry byte-identical to the
    /// untouched score -- the ops had not run. Asserting "more than one
    /// version" passed too, because the seeded library already has three. The
    /// only precondition that cannot be satisfied by an op that did nothing
    /// is the geometry CHANGING: if adding a staff, a tab and chords leaves
    /// the drawing identical, the fixture is broken and this test must say so
    /// rather than report "no collapse" about a score nothing happened to.
    func testTheCombinedOpThroughTheAppKeepsItsSystems() {
        func measure(_ arguments: [String]) -> String {
            app = XCUIApplication()
            app.launchArguments = ["-resetLibrary", "-seedTestLibrary",
                                   "-geometryProbe"] + arguments
            app.launch()
            XCUIDevice.shared.orientation = .portrait
            guard openTheFixture() else { return "" }
            let seen = waitForProbe()
            app.terminate()
            return seen
        }

        let control = measure([])
        let combined = measure(["-seedCombinedOp"])
        print("PROBE control:  \(control)")
        print("PROBE combined: \(combined)")
        snap("combined-op-through-the-app")

        XCTAssertFalse(systems(in: control).isEmpty, "no control geometry")
        XCTAssertFalse(systems(in: combined).isEmpty, "no combined geometry")
        XCTAssertNotEqual(combined, control,
                          "adding a staff, a tab and chords changed the "
                          + "drawing not at all (\(combined)) -- the fixture "
                          + "did not run, so this test can say nothing about #4")

        let lines = systems(in: combined).reduce(0, +)
        XCTAssertGreaterThan(lines, 1,
                             "the whole score is on ONE system -- Ali's "
                             + "collapse: \(combined)")
    }
}
