import XCTest

/// Getting a score OUT of the app, driven the way a reader drives it.
///
/// The engine's side of export is covered several ways over -- check_export.py,
/// check_render.py, ScoreExportTests on the filename -- and none of them
/// touches the journey: score, More, Export, a row per format, and a real file
/// handed to the system share sheet. Every one of those steps is app code that
/// nothing ran.
///
/// THE SHARE SHEET IS APPLE'S, and it is this app's one modal on purpose
/// (SystemShareSheet: the no-modal rule is about surfaces this app invents).
/// What is asserted about it is what a reader sees: it came up, and the file
/// on it carries the ARRANGEMENT's name and the format's extension -- not
/// "v003.musicxml", which is what the naming rule exists to prevent.
///
/// Three formats, and each is fetched differently: MusicXML is a copy of the
/// version artifact, MIDI is written by the engine, and the PDF is engraved on
/// device by the same renderer that draws the page (a PDF from the bridge
/// would not carry the chord adjustments and fingerings the Swift pass
/// applies). A test that took one format on trust would miss two thirds of it.
final class ExportFromTheApp: XCTestCase {

    private var app: XCUIApplication!

    /// The rows the Export screen offers, and the extension each must produce.
    /// Bound to `ScoreExport.Format` by ScoreExportTests, which asserts that
    /// these are exactly the formats and extensions the enum carries -- this
    /// bundle has no host app and cannot read the enum itself.
    private let formats = [("musicxml", "musicxml"), ("midi", "mid"), ("pdf", "pdf")]

    /// What the system sheet may say that proves the file went over as that
    /// KIND of file -- the extension it kept on the name, or the type iOS
    /// resolved and printed underneath. Lower-cased; any one of them will do.
    /// Written without the dot on purpose: the caption resolves ASYNCHRONOUSLY
    /// and the sheet says two different things while it does. Caught the first
    /// time this ran: the screenshot taken the moment the sheet appeared reads
    /// "Sous le ciel quartet.musicxml" with no second line, and a second later
    /// the same sheet reads "Sous le ciel quartet" over "MusicXML score ·
    /// 591 KB". Both name the type; neither is worth racing.
    private let marks = ["musicxml": ["musicxml"],
                         "midi": [".mid", "midi", "audio"],
                         "pdf": ["pdf"]]

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func openTheScore() -> Bool {
        _ = element("library-search").waitForExistence(timeout: 240)
        let row = element("row-sous-le-ciel-de-paris")
        guard row.waitForExistence(timeout: 300) else { return false }
        row.tap()
        let choice = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@",
                                  "arrangement-choice-")).firstMatch
        if choice.waitForExistence(timeout: 60) { choice.tap() }
        return app.buttons["score-title"].waitForExistence(timeout: 300)
    }

    /// Apple's sheet, by the identifier UIActivityViewController gives its own
    /// list. Present on both the iPad popover and the phone's sheet.
    private var shareSheet: XCUIElement {
        app.otherElements["ActivityListView"]
    }

    private func dismissShareSheet() {
        // The sheet's own X, by the identifier it carries. The popover dismiss
        // region behind it is raised SEVERAL times over and a query on it is
        // ambiguous -- which is what the first run of this test found.
        let close = app.buttons.matching(identifier: "header.closeButton").firstMatch
        if close.exists {
            close.tap()
        } else if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        } else {
            app.otherElements.matching(identifier: "PopoverDismissRegion")
                .firstMatch.tap()
        }
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: shareSheet)
        _ = XCTWaiter.wait(for: [gone], timeout: 30)
    }

    /// What the system sheet SAYS about the file it was handed: the name on
    /// top, and underneath it the type and size iOS read off the file itself.
    /// Both are Apple's own identifiers, taken from the element tree of a real
    /// run rather than guessed at.
    private func header() -> (name: String, detail: String) {
        let top = app.descendants(matching: .any)
            .matching(identifier: "LP.CaptionBar.TopCaption").firstMatch
        let bottom = app.descendants(matching: .any)
            .matching(identifier: "LP.CaptionBar.BottomCaption").firstMatch
        return (top.exists ? top.label : "",
                bottom.exists ? bottom.label : "")
    }

    /// Anything on screen whose label carries this text. The file's name is
    /// drawn by the system sheet, so it is read by label rather than by an
    /// identifier this app could have set.
    private func labelled(containing text: String) -> XCUIElementQuery {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", text))
    }

    func testEveryFormatHandsARealFileToTheShareSheet() {
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-resetViewPreferences",
                               "-seedTestLibrary"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        guard openTheScore() else { return XCTFail("the score never opened") }

        app.buttons["score-more"].tap()
        let exportRow = element("more-export")
        XCTAssertTrue(exportRow.waitForExistence(timeout: 60), "no Export row in More")
        // The row says which formats are behind it before it is opened.
        XCTAssertTrue(exportRow.label.contains("MusicXML")
                      || labelled(containing: "MusicXML · MIDI · PDF").count > 0,
                      "the More row does not name the formats: \(exportRow.label)")
        exportRow.tap()
        XCTAssertTrue(element("export-musicxml").waitForExistence(timeout: 60),
                      "the Export screen never opened")
        snap("01-the-export-screen")

        // The arrangement's own name, which is what the file must be called.
        // The title button's label is the whole line it reads out --
        // "Sous le ciel quartet, Sous le ciel de Paris · v003" -- and the
        // arrangement is the part before the comma.
        let title = app.buttons["score-title"].label
            .components(separatedBy: ",").first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        XCTAssertFalse(title.isEmpty, "the score bar has no title to name a file after")

        for (format, ext) in formats {
            let row = element("export-\(format)")
            XCTAssertTrue(row.waitForExistence(timeout: 60),
                          "no row for \(format) -- the screen offers "
                          + "\(formats.map(\.0)) and this one is missing")
            row.tap()

            // The wait is on what the app RAISES, not on a wall-clock budget:
            // a PDF of a long score is engraved on device, and how long that
            // takes is a property of the host.
            XCTAssertTrue(shareSheet.waitForExistence(timeout: 300),
                          "\(format): no share sheet -- nothing was handed over")
            snap("02-share-sheet-\(format)")

            // A real file, with the right type and a name a person can use.
            let (name, detail) = header()
            print("EXPORT \(format): name '\(name)' detail '\(detail)'")
            XCTAssertTrue(name.contains(title),
                          "\(format): the file is called '\(name)' and not after "
                          + "the arrangement ('\(title)') -- which is the whole "
                          + "point of the naming rule")
            // THE TYPE, and it is read two ways because iOS shows it two ways:
            // a type it knows is named underneath ("PDF Document · 61 KB") and
            // the extension comes off the title; a type it does not know
            // (MusicXML) keeps the extension on the title instead. Either is
            // proof the file went over as that kind of file; neither is
            // something this app writes, so both are taken as found.
            let says = (name + " " + detail).lowercased()
            XCTAssertTrue(marks[format]!.contains { says.contains($0) },
                          "\(format): the sheet describes '\(name)' / '\(detail)', "
                          + "which names none of \(marks[format]!)")
            if !detail.isEmpty {
                XCTAssertFalse(detail.lowercased().contains("zero"),
                               "\(format): the file handed over is empty: \(detail)")
            }
            // ...and iOS resolved it as something it can do things with.
            XCTAssertGreaterThan(
                shareSheet.cells.matching(identifier: "shareCell").count, 0,
                "\(format): the sheet came up with nothing to do to the file")

            dismissShareSheet()
            XCTAssertTrue(element("export-\(format)").waitForExistence(timeout: 60),
                          "\(format): the Export screen did not come back")
        }
        snap("03-back-on-the-export-screen")
    }

    /// The other row on the same screen: the arrangement itself, as one file
    /// for another iPad. It shares the sheet and the same failure modes.
    func testTheBundleRowAlsoHandsOverAFile() {
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-resetViewPreferences",
                               "-seedTestLibrary"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        guard openTheScore() else { return XCTFail("the score never opened") }
        app.buttons["score-more"].tap()
        guard element("more-export").waitForExistence(timeout: 60) else {
            return XCTFail("no Export row in More")
        }
        element("more-export").tap()
        let bundle = element("export-bundle")
        XCTAssertTrue(bundle.waitForExistence(timeout: 60), "no bundle row")
        bundle.tap()
        XCTAssertTrue(shareSheet.waitForExistence(timeout: 300),
                      "the bundle was never handed over")
        snap("04-share-sheet-bundle")
        let (name, detail) = header()
        print("EXPORT bundle: name '\(name)' detail '\(detail)'")
        // A bundle is named for the arrangement's SLUG -- it is the library's
        // own handle on it and not a title anybody typed -- and iOS knows a
        // .scorbundle as a zip, so it names the type and the size underneath
        // rather than keeping the extension on the name.
        XCTAssertTrue(name.contains("sous-le-ciel"),
                      "the bundle is called '\(name)'")
        XCTAssertTrue(detail.lowercased().contains("archive")
                      || name.lowercased().contains(".scorbundle"),
                      "the file handed over is not an archive: '\(name)' / '\(detail)'")
        XCTAssertFalse(detail.lowercased().contains("zero"),
                       "the bundle handed over is empty: \(detail)")
        dismissShareSheet()
    }
}
