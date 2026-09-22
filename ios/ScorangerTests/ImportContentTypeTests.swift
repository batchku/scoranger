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
        for suffix in ["musicxml", "mxl", "xml", "mid", "midi", "abc", "pdf"] {
            guard let type = UTType(filenameExtension: suffix) else { continue }
            XCTAssertTrue(declared.contains { type.conforms(to: $0) || type == $0 },
                          ".\(suffix) stopped being selectable")
        }
    }

    /// §15's own assertion, in one line: the array that greys images out now
    /// includes them.
    func testFilesOfferPictures() {
        let declared = Set(ImportKind.file.contentTypes.map(\.identifier))
        XCTAssertTrue(declared.isSuperset(of: ["public.jpeg", "public.png",
                                               "public.heic", "public.image"]),
                      "the picker still greys pictures out: \(declared.sorted())")
    }

    /// BOTH IMAGE ROUTES END IN THE SAME PIPELINE (§15 ruling 1).
    ///
    /// A picture from Files and a picture from the camera roll are the same
    /// thing once there is a file, and this is the guard against them drifting
    /// into two. `receiveFile` sends anything that is not notation down the
    /// scan path -- so an image and a PDF take the identical branch, and a
    /// change that special-cased one would fail here.
    func testAnImageImportsLikeAScan() {
        for picture in ["page.jpg", "page.jpeg", "page.png", "page.heic",
                        "IMG_0421.HEIC", "Screenshot.PNG"] {
            let kind = ScoreArtifact.kind(ofFile: picture)
            XCTAssertEqual(kind, .image, "\(picture) is not seen as a picture")
            XCTAssertFalse(kind.isNotation,
                           "\(picture) would take the notation path, not the "
                           + "scan path a PDF takes")
        }
        // The same branch, reached by the thing it has to match.
        XCTAssertFalse(ScoreArtifact.kind(ofFile: "scan.pdf").isNotation)
        // And notation is still notation, so "same pipeline" has not become
        // "one pipeline for everything".
        for notation in ["piece.musicxml", "piece.mxl", "piece.mid", "reel.abc"] {
            XCTAssertTrue(ScoreArtifact.kind(ofFile: notation).isNotation)
        }
    }

    /// ABC IS NOTATION, NOT A SCAN.
    ///
    /// `ScoreArtifact.kind` falls through to `.scan` for anything it does not
    /// recognise, so an unlisted `.abc` is not rejected -- it is mis-filed as
    /// a PDF and sent to `importPDF`, which stores the text file as a picture
    /// of music nothing can edit. That is the failure this pins.
    func testABCTakesTheNotationPath() {
        for tune in ["kesh.abc", "Drowsy Maggie.ABC", "set.abc"] {
            XCTAssertEqual(ScoreArtifact.kind(ofFile: tune), .notation,
                           "\(tune) would be stored as a scan")
        }
        XCTAssertTrue(ScoreArtifact.notationSuffixes.contains("abc"),
                      "the Swift list has drifted from workspace.NOTATION_SUFFIXES")
    }

    /// `.abc` IS ALREADY TAKEN, and the picker has to know it.
    ///
    /// The premise this was built on -- that ABC has no system UTType and
    /// needs its own -- is false. The system declares `.abc` as Alembic,
    /// Pixar's 3D scene cache, so `UTType(filenameExtension: "abc")` is
    /// `public.alembic`, and that is what a tune downloaded from
    /// thesession.org is tagged as. An app offering only `com.scoranger.abc`
    /// would grey out every real tune.
    ///
    /// One extension, two formats, one system type. This pins the resolution
    /// so a change that drops `public.alembic` from the list -- which reads
    /// like tidying up a wrong-looking entry -- fails here rather than in a
    /// reader's Files app.
    func testABCResolvesToAlembicAndThePickerTakesItAnyway() {
        guard let abc = UTType(filenameExtension: "abc") else {
            return XCTFail("no UTType resolves for .abc at all")
        }
        XCTAssertFalse(abc.isDynamic, "\(abc.identifier) is dynamic")
        XCTAssertEqual(abc.identifier, "public.alembic",
                       "the system no longer claims .abc for Alembic -- if it "
                       + "claims nothing, com.scoranger.abc can own the "
                       + "extension and Alternate rank should become Owner")
        let declared = ImportKind.file.contentTypes
        XCTAssertTrue(declared.contains(abc),
                      "the picker does not accept what a downloaded tune is "
                      + "actually tagged as: \(declared.map(\.identifier))")
    }

    /// THE APP'S OWN TYPE IS NOT ASSERTED HERE, AND CANNOT BE.
    ///
    /// `com.scoranger.abc` is declared in the app's Info.plist and this
    /// bundle has no host app, so whether it resolves in THIS process depends
    /// on whether something else has already installed the app on the
    /// simulator. Run alone it is absent; run in the gate, after the UI
    /// bundle has installed the app, it is present. An assertion either way
    /// pins the run order rather than the product, and the first version of
    /// this test asserted the absence and duly failed in the gate only.
    ///
    /// The declaration is checked where it is deterministic instead: against
    /// the generated Info.plist itself, in engine/scripts/check_abc_import.py.
    /// What IS asserted above is the one a reader feels -- the picker accepts
    /// the type a downloaded `.abc` file actually carries.

    /// The umbrella is safe because the PIPELINE normalises, not because the
    /// picker narrows. Anything the engine will not take is converted at the
    /// one entry point both routes share.
    func testTheUmbrellaIsMadeSafeByNormalising() {
        // Already acceptable: handed back untouched, no needless rewrite.
        let jpeg = FileManager.default.temporaryDirectory
            .appending(path: "already.jpg")
        XCTAssertEqual(ScanImage.normalised(jpeg), jpeg)
        // Not an image at all: refused, rather than a blank page in the
        // library that nobody can tell from a failed load.
        let nonsense = FileManager.default.temporaryDirectory
            .appending(path: "not-an-image-\(UUID().uuidString).tiff")
        try? Data("not an image".utf8).write(to: nonsense)
        XCTAssertNil(ScanImage.normalised(nonsense))
    }

    /// The picker offers nothing the pipeline would then refuse -- and since
    /// §15 the umbrella is included, so the claim is carried by
    /// `ScanImage.normalised` rather than by the list being short.
    ///
    /// Each declared image type is either one the engine takes by name, or the
    /// umbrella, which normalising makes good. A type that was neither would
    /// be a picture a reader could choose and nothing could import.
    func testThePickerOffersNothingThePipelineWouldRefuse() {
        let accepted = ScoreArtifact.imageSuffixes
        for type in ImportKind.file.contentTypes where type.conforms(to: .image) {
            if type == .image { continue }   // the umbrella, normalised
            let suffixes = Set(type.tags[.filenameExtension] ?? [])
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
