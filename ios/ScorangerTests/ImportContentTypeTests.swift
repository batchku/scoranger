import UniformTypeIdentifiers
import XCTest

/// What the file picker will LET the reader choose.
///
/// Ali, from Files: his "Score-image-test.jpg", a PNG and his screenshots are
/// all greyed out, while PDFs and documents are selectable. 0.6.13 taught the
/// import handler about images -- they arrive fine through share-in and the
/// inbox -- and nobody told the picker, so the one route a reader actually
/// looks for was the one route that refused them.
///
/// The bug is a DRIFT between two lists that have to agree: what the pipeline
/// accepts (`ScoreArtifact.imageSuffixes`, and the engine's own
/// `IMAGE_SUFFIXES` beside it) and what the picker declares. So the assertion
/// here is the relationship rather than a second copy of the list -- a list
/// asserted against itself would have passed in 0.6.13 too.
final class ImportContentTypeTests: XCTestCase {

    // MARK: - The invariant that was broken

    /// EVERY suffix the app will import as an image is selectable in the
    /// picker. This is the test that would have caught it.
    func testEveryImageTheAppAcceptsIsSelectableInThePicker() {
        let declared = ImportKind.file.contentTypes
        for suffix in ScoreArtifact.imageSuffixes.sorted() {
            guard let type = UTType(filenameExtension: suffix) else {
                XCTFail("the system does not know the type of .\(suffix)")
                continue
            }
            let offered = declared.contains { type.conforms(to: $0) || type == $0 }
            XCTAssertTrue(offered,
                          ".\(suffix) is something this app imports and the "
                          + "picker will not let anyone choose it. Declared: "
                          + "\(declared.map(\.identifier))")
        }
    }

    /// And the same for the notation and PDF it always took, so widening the
    /// list cannot quietly narrow it.
    func testTheScoreTypesItAlwaysTookAreStillThere() {
        let declared = ImportKind.file.contentTypes
        for suffix in ["musicxml", "mxl", "xml", "mid", "midi", "pdf"] {
            guard let type = UTType(filenameExtension: suffix) else { continue }
            XCTAssertTrue(declared.contains { type.conforms(to: $0) || type == $0 },
                          ".\(suffix) stopped being selectable")
        }
    }

    /// The picker offers NOTHING the pipeline would then refuse.
    ///
    /// The other half, and the reason `public.image` is not among the declared
    /// types. An umbrella would make a GIF or a TIFF selectable, and the
    /// engine takes four image suffixes -- so the reader would get past the
    /// grey and into a failed import, which is the same bug wearing better
    /// clothes. When the engine widens, this test is what says the picker may
    /// widen with it.
    func testThePickerOffersNothingThePipelineWouldRefuse() {
        let accepted = ScoreArtifact.imageSuffixes
        for type in ImportKind.file.contentTypes where type.conforms(to: .image) {
            let suffixes = Set(type.tags[.filenameExtension] ?? [])
            XCTAssertFalse(suffixes.isEmpty,
                           "\(type.identifier) names no file extension, so it "
                           + "is an umbrella and cannot be checked against "
                           + "what the engine takes")
            XCTAssertFalse(suffixes.isDisjoint(with: accepted),
                           "\(type.identifier) is selectable but none of its "
                           + "extensions \(suffixes.sorted()) is one the "
                           + "engine imports \(accepted.sorted())")
        }
    }

    /// A folder is a folder and a book is a PDF: widening the file picker must
    /// not widen the other two.
    func testTheOtherTwoIntentsAreUnchanged() {
        XCTAssertEqual(ImportKind.folder.contentTypes, [.folder])
        XCTAssertEqual(ImportKind.book.contentTypes, [.pdf])
    }

    /// The three concrete image types, named, so a reader of this file can see
    /// what a reader of Files can choose.
    func testTheImageTypesAreTheOnesTheEngineTakes() {
        let declared = Set(ImportKind.file.contentTypes.map(\.identifier))
        for expected in [UTType.jpeg, .png, .heic] {
            XCTAssertTrue(declared.contains(expected.identifier),
                          "\(expected.identifier) is not offered")
        }
    }
}
