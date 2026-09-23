import XCTest

/// The credits screen shows a licence text as it ships (0.15.0). Until then
/// vendor_engine.sh deleted each Python package's .dist-info and its LICENSE
/// with it, and the screen said the texts were in the repository -- which a
/// binary distribution under BSD-3, MIT, Apache-2.0 or MPL-2.0 does not
/// satisfy.
final class LicenceTextTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LicenceTextTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ text: String, to path: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// requests carries a LICENSE and a NOTICE, and Apache-2.0 requires both.
    func testAFolderIsEveryFileInItInNameOrder() throws {
        try write("notice", to: "licences/requests/NOTICE")
        try write("licence", to: "licences/requests/LICENSE")
        let files = try LicenceText.read("licences/requests", under: root)
        XCTAssertEqual(files, [.init(name: "LICENSE", text: "licence"),
                               .init(name: "NOTICE", text: "notice")])
    }

    /// CPython's LICENSE.txt sits in the standard library's own folder, which
    /// is not a licence text.
    func testAFileIsTheWholeText() throws {
        try write("psf", to: "python/lib/LICENSE.txt")
        try write("print()", to: "python/lib/os.py")
        XCTAssertEqual(try LicenceText.read("python/lib/LICENSE.txt", under: root),
                       [.init(name: "LICENSE.txt", text: "psf")])
    }

    func testAMissingOrEmptyTextIsAFailureAndNotAnEmptySheet() throws {
        XCTAssertThrowsError(try LicenceText.read("licences/absent", under: root)) {
            XCTAssertEqual($0 as? LicenceText.Failure, .missing("licences/absent"))
        }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("licences/empty"), withIntermediateDirectories: true)
        try write("", to: "licences/empty/.DS_Store")
        XCTAssertThrowsError(try LicenceText.read("licences/empty", under: root)) {
            XCTAssertEqual($0 as? LicenceText.Failure, .missing("licences/empty"),
                           "a folder holding only hidden files holds no text")
        }
    }

    func testATextThatIsNotUTF8IsReportedByName() throws {
        let url = root.appendingPathComponent("licences/odd/LICENSE")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data([0xFF, 0xFE, 0xFD]).write(to: url)
        XCTAssertThrowsError(try LicenceText.read("licences/odd", under: root)) {
            XCTAssertEqual($0 as? LicenceText.Failure, .unreadable("licences/odd/LICENSE"))
        }
    }

    func testParagraphsKeepEveryLineBreakInsideThem() {
        let text = "Copyright 2020\nAll rights reserved.\n\n\n1. Keep this.\n   Indented.\r\n\r\nEnd\n"
        XCTAssertEqual(LicenceText.paragraphs(text),
                       ["Copyright 2020\nAll rights reserved.", "1. Keep this.\n   Indented.", "End"])
    }
}
