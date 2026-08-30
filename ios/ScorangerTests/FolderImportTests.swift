import XCTest

/// The plan a reader reads before their library exists.
final class FolderImportTests: XCTestCase {
    private let folder = URL(fileURLWithPath: "/tmp/All")

    private func payload(_ pieces: [[String: Any]],
                         ignored: [[String: Any]] = []) -> [String: Any] {
        ["plan": ["pieces": pieces, "ignored": ignored]]
    }

    func testItDecodesPiecesAndTheirArrangements() {
        let plan = FolderImportPlan.decode(payload([
            ["piece": "Sous le Ciel de Paris", "arrangements": [
                ["file": "a.pdf", "name": "Hubert Giraud", "kind": "pdf"],
                ["file": "b.pdf", "name": "Édith Piaf version", "kind": "pdf"]]],
            ["piece": "Bucimis", "arrangements": [
                ["file": "c.pdf", "name": "Bucimis", "kind": "pdf"]]],
        ]), folder: folder)
        XCTAssertEqual(plan?.pieces.count, 2)
        XCTAssertEqual(plan?.arrangementCount, 3)
        XCTAssertEqual(plan?.pieces.first?.arrangements.first?.name, "Hubert Giraud")
        XCTAssertEqual(plan?.pieces.first?.arrangements.first?.kind, "pdf")
    }

    func testTheSummarySaysWhatWillHappen() {
        let plan = FolderImportPlan.decode(payload([
            ["piece": "One", "arrangements": [["file": "a.pdf", "name": "a", "kind": "pdf"]]],
            ["piece": "Two", "arrangements": [["file": "b.pdf", "name": "b", "kind": "pdf"]]],
        ]), folder: folder)
        XCTAssertEqual(plan?.summary, "2 pieces, 2 arrangements")
    }

    func testItSingularisesOnePiece() {
        let plan = FolderImportPlan.decode(payload([
            ["piece": "Only", "arrangements": [["file": "a.pdf", "name": "a", "kind": "pdf"]]],
        ]), folder: folder)
        XCTAssertEqual(plan?.summary, "1 piece, 1 arrangement")
    }

    /// Files that are not scores are counted, so the reader can see that the
    /// numbers add up and nothing quietly vanished.
    func testIgnoredFilesAreCounted() {
        let plan = FolderImportPlan.decode(
            payload([["piece": "One", "arrangements": [["file": "a.pdf", "name": "a", "kind": "pdf"]]]],
                    ignored: [["file": "notes.txt"], ["file": ".DS_Store"]]),
            folder: folder)
        XCTAssertEqual(plan?.ignored, 2)
    }

    /// A shape the engine did not promise is refused rather than imported as a
    /// guess — this writes across a whole library.
    func testAnUnexpectedShapeIsRefused() {
        XCTAssertNil(FolderImportPlan.decode([:], folder: folder))
        XCTAssertNil(FolderImportPlan.decode(["plan": ["pieces": "not a list"]],
                                             folder: folder))
    }

    func testAnEmptyFolderPlansNothing() {
        let plan = FolderImportPlan.decode(payload([]), folder: folder)
        XCTAssertEqual(plan?.isEmpty, true)
        XCTAssertEqual(plan?.arrangementCount, 0)
    }
}
