import XCTest

/// Photo is in the Import band, and it opens the camera roll.
///
/// Ali: "in addition to opening files, I need an option to open the local
/// photo gallery too." Files cannot reach the camera roll, and a photographed
/// page is how a score arrives when it is not already a file.
///
/// What this can assert from out here is the affordance and the presentation:
/// the entry exists where §14's band puts it, tapping it presents Apple's own
/// picker, and the picker can be dismissed without leaving the app somewhere
/// odd. What happens to a chosen photo is `PhotoImport`'s own path into
/// `receiveFile`, which is the same entry point every filed score uses.
final class ImportFromPhotos: XCTestCase {

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testPhotoIsOfferedAndOpensTheGallery() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-seedTestLibrary"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        let search = app.descendants(matching: .any)["library-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 240),
                      "the library never appeared")
        settle(search, still: 0.8)

        app.descendants(matching: .any)["library-import"].firstMatch.tap()
        let photo = app.descendants(matching: .any)["library-import-photo"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 20),
                      "Photo is not in the Import band")
        XCTAssertTrue(photo.isHittable)
        snap("import-band-with-photo")

        photo.tap()
        // PHPicker runs OUT OF PROCESS, so it is not part of this app's
        // element tree: it is found through the springboard. Its Cancel is
        // the one thing reliably addressable in every locale this runs in.
        let gallery = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow")
        let cancel = app.buttons["Cancel"].firstMatch
        let appeared = cancel.waitForExistence(timeout: 20)
            || gallery.wait(for: .runningForeground, timeout: 20)
        XCTAssertTrue(appeared,
                      "tapping Photo did not present the photo picker")
        snap("photo-picker-open")

        if cancel.exists { cancel.tap() }
        XCTAssertTrue(search.waitForExistence(timeout: 30),
                      "dismissing the photo picker did not return to the library")
    }
}
