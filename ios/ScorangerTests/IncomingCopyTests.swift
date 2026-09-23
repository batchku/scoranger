import XCTest

/// The private copy every import takes of an incoming file (0.14.1).
///
/// It moved off the main thread; what must not change is what it does: the
/// copy lands whole, a stale file of the same name from an earlier arrival is
/// replaced rather than refusing the new one, and a source that is gone is an
/// error the import reports rather than a silent nothing.
final class IncomingCopyTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appending(path: "IncomingCopyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testTheCopyLandsWhole() async throws {
        let source = dir.appending(path: "Tunebook.pdf")
        let bytes = Data((0..<200_000).map { UInt8($0 % 251) })
        try bytes.write(to: source)
        let copy = dir.appending(path: "held.pdf")
        try await IncomingCopy.make(source, at: copy)
        XCTAssertEqual(try Data(contentsOf: copy), bytes)
    }

    func testAnEarlierArrivalOfTheSameNameIsReplaced() async throws {
        let source = dir.appending(path: "Reel.musicxml")
        try Data("new".utf8).write(to: source)
        let copy = dir.appending(path: "held.musicxml")
        try Data("stale".utf8).write(to: copy)
        try await IncomingCopy.make(source, at: copy)
        XCTAssertEqual(try String(contentsOf: copy, encoding: .utf8), "new")
    }

    func testAMissingSourceIsAnError() async {
        let missing = dir.appending(path: "gone.pdf")
        do {
            try await IncomingCopy.make(missing, at: dir.appending(path: "held.pdf"))
            XCTFail("copying a file that is not there succeeded")
        } catch {
            // the import that called it says so
        }
    }
}
