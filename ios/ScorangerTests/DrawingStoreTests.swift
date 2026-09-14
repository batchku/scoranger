import PencilKit
import XCTest

/// A reader's pencil marks, and the two renames that could have lost them.
///
/// Markup lives outside the workspace, in `Documents/annotations`, keyed
/// `<namespace>/<version>/p<N>`. BOTH halves of that key moved in the 0.7 line:
/// a version's id became opaque (design/FIREBASE.md §3), and the namespace
/// became the score's uid rather than its slug, because a slug is
/// `slugify(name)` -- it moves when the score is renamed, and it means nothing
/// on the device a bundle is opened on (§13.3).
///
/// Nothing deletes the old files, so the failure this guards is quiet: markup
/// still on disk and never looked up again. Every test here writes a real
/// `PKDrawing`, runs the migration, and reads it back through the key the app
/// would now ask for.
final class DrawingStoreTests: XCTestCase {

    private var dir: URL!
    private var store: DrawingStore!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appending(path: "ink-\(UUID().uuidString)")
        store = DrawingStore(dir: dir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - fixtures

    /// A drawing with one stroke, so "did the bytes survive" is answerable.
    private func aDrawing() -> PKDrawing {
        let ink = PKInk(.pen, color: .black)
        let points = (0..<8).map {
            PKStrokePoint(location: CGPoint(x: Double($0) * 10, y: 20),
                          timeOffset: Double($0) * 0.01, size: CGSize(width: 3, height: 3),
                          opacity: 1, force: 1, azimuth: 0, altitude: 0)
        }
        return PKDrawing(strokes: [PKStroke(ink: ink, path: PKStrokePath(controlPoints: points,
                                                                        creationDate: Date()))])
    }

    private func version(_ id: String, label: String?) -> VersionDoc {
        VersionDoc(id: id, label: label, file: "\(id).musicxml", op: "import")
    }

    private func score(slug: String, uid: String?, versions: [VersionDoc]) -> ScoreDoc {
        ScoreDoc(slug: slug, uid: uid, name: slug, versions: versions, sources: nil)
    }

    private func manifest(_ scores: [ScoreDoc]) -> Manifest {
        Manifest(scores: scores)
    }

    private var filenames: Set<String> {
        Set(((try? FileManager.default.contentsOfDirectory(at: dir,
                                                           includingPropertiesForKeys: nil)) ?? [])
            .map { $0.lastPathComponent })
    }

    // MARK: - a shared set list's markup is not this migration's business

    /// A shared entry's markup is keyed on the ENTRY, which is already the same
    /// string on every device and has no older spelling to migrate from.
    ///
    /// The reason this is a test and not a comment: an arrangement a reader
    /// names "Shared" slugs to `shared`, and then a shared key and a local one
    /// differ only by whether the next component is an entry id or a version
    /// id. Give that score a version whose id happens to match an entry id and
    /// the migration would re-file a band's markup under one person's local
    /// arrangement -- where the other members would never see it again, and
    /// where nothing would report it missing.
    func testASharedEntrysMarkupIsLeftWhereItIs() {
        let entry = "01ENTRY"
        store.save(aDrawing(), for: "shared/\(entry)/01VID/p0")

        // The pathological library: a score actually slugged `shared`, whose
        // version id IS the entry id.
        let moved = store.migrateKeys(manifest: manifest([
            score(slug: "shared", uid: "01SCOREUID",
                  versions: [version(entry, label: "v001")]),
        ]))

        XCTAssertFalse(store.drawing(for: "shared/\(entry)/01VID/p0").strokes.isEmpty,
                       "the band's markup moved out from under the set list")
        XCTAssertTrue(filenames.contains("shared_\(entry)_01VID_p0.pkdrawing"))
        XCTAssertEqual(moved, 0, "nothing in this library needed migrating")
    }

    /// And a LOCAL arrangement still migrates while a shared key sits beside
    /// it, so the hold-out is a filter and not an early return.
    func testALocalArrangementStillMigratesAlongsideSharedMarkup() {
        store.save(aDrawing(), for: "shared/01ENTRY/01VID/p0")
        store.save(aDrawing(), for: "jig/v002/p0")

        let moved = store.migrateKeys(manifest: manifest([
            score(slug: "jig", uid: "jig", versions: [version("01VID", label: "v002")]),
        ]))

        XCTAssertEqual(moved, 1)
        XCTAssertFalse(store.drawing(for: "jig/01VID/p0").strokes.isEmpty)
        XCTAssertFalse(store.drawing(for: "shared/01ENTRY/01VID/p0").strokes.isEmpty)
    }

    // MARK: - the two hops

    /// The version hop alone: markup filed under `v002` is found under the id.
    func testMarkupFiledUnderTheOldVersionLabelIsFoundUnderTheId() {
        store.save(aDrawing(), for: "jig/v002/p0")

        let moved = store.migrateKeys(manifest: manifest([
            score(slug: "jig", uid: "jig", versions: [version("01VID", label: "v002")]),
        ]))

        XCTAssertEqual(moved, 1)
        XCTAssertFalse(store.drawing(for: "jig/01VID/p0").strokes.isEmpty)
    }

    /// The namespace hop alone: markup filed under the slug is found under the
    /// uid. This is the one the bundle needs -- the receiving device's slug for
    /// the same music is whatever `slugify` makes of the title it already has.
    func testMarkupFiledUnderTheSlugIsFoundUnderTheUid() {
        store.save(aDrawing(), for: "morrisons-jig/01VID/p3")

        let moved = store.migrateKeys(manifest: manifest([
            score(slug: "morrisons-jig", uid: "01SCORE",
                  versions: [version("01VID", label: "v001")]),
        ]))

        XCTAssertEqual(moved, 1)
        XCTAssertFalse(store.drawing(for: "01SCORE/01VID/p3").strokes.isEmpty)
    }

    /// Both hops at once, which is what a library migrated straight from before
    /// stage 0 actually presents. One move, not two, and no half-migrated key
    /// left behind.
    func testBothHopsAreOneMove() {
        store.save(aDrawing(), for: "morrisons-jig/v002/p1")

        let moved = store.migrateKeys(manifest: manifest([
            score(slug: "morrisons-jig", uid: "01SCORE",
                  versions: [version("01VID", label: "v002")]),
        ]))

        XCTAssertEqual(moved, 1)
        XCTAssertFalse(store.drawing(for: "01SCORE/01VID/p1").strokes.isEmpty)
        XCTAssertEqual(filenames, ["01SCORE_01VID_p1.pkdrawing"],
                       "the intermediate key must not survive as a second file")
    }

    // MARK: - the properties that make it safe to run

    /// Idempotent: running it again moves nothing and loses nothing.
    func testRunningTwiceChangesNothing() {
        store.save(aDrawing(), for: "morrisons-jig/v002/p1")
        let m = manifest([score(slug: "morrisons-jig", uid: "01SCORE",
                                versions: [version("01VID", label: "v002")])])

        XCTAssertEqual(store.migrateKeys(manifest: m), 1)
        XCTAssertEqual(store.migrateKeys(manifest: m), 0)
        XCTAssertFalse(store.drawing(for: "01SCORE/01VID/p1").strokes.isEmpty)
    }

    /// It never overwrites. If the reader has already drawn on the new key, the
    /// old file is left where it is rather than clobbering live markup -- the
    /// stale copy is recoverable, the overwritten one is not.
    func testAnOccupiedDestinationIsNotOverwritten() {
        store.save(aDrawing(), for: "morrisons-jig/v002/p1")   // the old one
        let live = aDrawing()
        store.save(live, for: "01SCORE/01VID/p1")              // already drawn

        let moved = store.migrateKeys(manifest: manifest([
            score(slug: "morrisons-jig", uid: "01SCORE",
                  versions: [version("01VID", label: "v002")]),
        ]))

        XCTAssertEqual(moved, 0)
        XCTAssertEqual(store.drawing(for: "01SCORE/01VID/p1").strokes.count,
                       live.strokes.count)
        XCTAssertTrue(filenames.contains("morrisons-jig_v002_p1.pkdrawing"),
                      "the source is kept, not deleted")
    }

    /// Every page of a version moves, not just the first.
    func testEveryPageMoves() {
        for page in 0..<4 { store.save(aDrawing(), for: "jig/v001/p\(page)") }

        let moved = store.migrateKeys(manifest: manifest([
            score(slug: "jig", uid: "01SCORE", versions: [version("01VID", label: "v001")]),
        ]))

        XCTAssertEqual(moved, 4)
        for page in 0..<4 {
            XCTAssertFalse(store.drawing(for: "01SCORE/01VID/p\(page)").strokes.isEmpty)
        }
    }

    /// A score the engine has not given a uid yet keeps its markup where it is,
    /// reachable by the key `ScoreDoc.inkNamespace` hands out. The fallback and
    /// the migration have to agree, or the marks vanish until the next launch.
    func testAScoreWithNoUidKeepsItsMarkupReachable() {
        store.save(aDrawing(), for: "jig/01VID/p0")
        let doc = score(slug: "jig", uid: nil, versions: [version("01VID", label: "v001")])

        XCTAssertEqual(store.migrateKeys(manifest: manifest([doc])), 0)
        XCTAssertEqual(doc.inkNamespace, "jig")
        XCTAssertFalse(store.drawing(for: "\(doc.inkNamespace)/01VID/p0").strokes.isEmpty)
    }

    /// Two scores whose slugs share a prefix must not bleed into each other.
    /// `clear` already learned this ("blue" clearing "blue-bossa"); the
    /// migration matches on prefixes too and needs the same guarantee.
    func testAPrefixSharedBetweenTwoScoresDoesNotBleed() {
        store.save(aDrawing(), for: "blue/01A/p0")
        store.save(aDrawing(), for: "blue-bossa/01B/p0")

        let moved = store.migrateKeys(manifest: manifest([
            score(slug: "blue", uid: "01BLUE", versions: [version("01A", label: "v001")]),
            score(slug: "blue-bossa", uid: "01BOSSA", versions: [version("01B", label: "v001")]),
        ]))

        XCTAssertEqual(moved, 2)
        XCTAssertEqual(filenames, ["01BLUE_01A_p0.pkdrawing", "01BOSSA_01B_p0.pkdrawing"])
    }

    /// A rename no longer touches markup, because the key never held the slug.
    /// This is the orphaning bug the re-key exists to delete.
    func testARenameDoesNotOrphanMarkup() {
        let before = score(slug: "morrisons-jig", uid: "01SCORE",
                           versions: [version("01VID", label: "v001")])
        store.save(aDrawing(), for: "\(before.inkNamespace)/01VID/p0")

        // the engine renames the score; the slug moves, the uid does not
        let after = score(slug: "the-merry-blacksmith", uid: "01SCORE",
                          versions: [version("01VID", label: "v001")])

        XCTAssertEqual(store.migrateKeys(manifest: manifest([after])), 0)
        XCTAssertFalse(store.drawing(for: "\(after.inkNamespace)/01VID/p0").strokes.isEmpty)
    }
}
