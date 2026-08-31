import Foundation
import XCTest

/// Listing a chosen folder (`FolderScan`).
///
/// The bug these pin: Import Folder on an iCloud library found no files, so it
/// planned nothing and went back to the library in silence. Reading a file out
/// of that same folder worked -- only ENUMERATING it failed. The listing moved
/// into Swift, where the file provider is visible, and the engine is handed the
/// names it should group.
final class FolderScanTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root,
                                                withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ relative: String) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }

    /// The shape a Newzik export arrives in: one folder per piece, its files
    /// the arrangements. What the engine needs is "Piece/file.pdf".
    func testAFolderPerPieceComesBackAsRelativePaths() throws {
        try write("Jovano Jovanke/3. Jovano Jovanke (G).pdf")
        try write("Kaitarma/Kaitarma.pdf")
        try write("Nature Boy/lead.pdf")
        try write("Nature Boy/piano.musicxml")

        let found = Set(FolderScan.relativePaths(in: root))

        XCTAssertEqual(found, ["Jovano Jovanke/3. Jovano Jovanke (G).pdf",
                               "Kaitarma/Kaitarma.pdf",
                               "Nature Boy/lead.pdf",
                               "Nature Boy/piano.musicxml"])
    }

    /// The piece is the FIRST component, so the path has to stay relative to
    /// the folder the reader picked. An absolute path would make every file a
    /// member of one piece called "/" -- which is exactly what happens if the
    /// prefix is not stripped.
    func testPathsAreRelativeToTheChosenFolderNotAbsolute() throws {
        try write("Bucimis/Bucimis.pdf")

        let found = FolderScan.relativePaths(in: root)

        XCTAssertEqual(found, ["Bucimis/Bucimis.pdf"])
        XCTAssertFalse(found[0].hasPrefix("/"), "absolute path leaked out")
    }

    /// Directories are containers, not arrangements. An empty one contributes
    /// nothing rather than appearing as a file with no extension.
    func testDirectoriesThemselvesAreNotListed() throws {
        try write("Kopanitsa/Kopanitsa.pdf")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Empty Piece"),
            withIntermediateDirectories: true)

        let found = FolderScan.relativePaths(in: root)

        XCTAssertEqual(found, ["Kopanitsa/Kopanitsa.pdf"])
    }

    /// Newzik nests: a piece folder can hold a folder of its own.
    func testItReachesFilesMoreThanOneLevelDown() throws {
        try write("Misty/parts/violin.pdf")

        XCTAssertEqual(FolderScan.relativePaths(in: root), ["Misty/parts/violin.pdf"])
    }

    /// A folder that cannot be read lists nothing rather than trapping. The
    /// CALLER is what must speak up -- see AppState's empty-listing notice.
    func testAFolderThatIsNotThereListsNothing() {
        let gone = root.appendingPathComponent("no-such-folder")

        XCTAssertEqual(FolderScan.relativePaths(in: gone), [])
    }
}
