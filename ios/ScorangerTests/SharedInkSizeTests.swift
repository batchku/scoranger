import PencilKit
import XCTest

/// Does a real page of markup fit in a Firestore document?
///
/// design/FIREBASE.md §11.6 named this as the one thing in the shared-ink
/// design that was an ASSUMPTION rather than a measurement, and said it had to
/// stop being one before the build shipped. One participant's ink for a whole
/// arrangement is ONE document, pages inside it, and Firestore's 1 MiB limit
/// on a document is hard -- no configuration raises it. If a marked-up score
/// does not fit, the layout is wrong and it has to become a document per page
/// or a file in Storage, which are both worse in ways worth avoiding.
///
/// So this builds markup with the real PencilKit and measures the real
/// `dataRepresentation()`. It is not a mock: `PKDrawing`'s serialisation is
/// what the number depends on, and a fixture number would go stale the first
/// time Apple changed the format.
final class SharedInkSizeTests: XCTestCase {

    /// A stroke of `points` samples, as PencilKit records one.
    private func stroke(points: Int, at y: CGFloat) -> PKStroke {
        let path = PKStrokePath(controlPoints: (0..<points).map { i in
            PKStrokePoint(location: CGPoint(x: CGFloat(i) * 3, y: y),
                          timeOffset: Double(i) / 120,
                          size: CGSize(width: 3, height: 3),
                          opacity: 1, force: 0.6, azimuth: 0, altitude: .pi / 3)
        }, creationDate: Date())
        return PKStroke(ink: PKInk(.pen, color: .red), path: path)
    }

    /// What a heavily marked page actually costs.
    ///
    /// Sixty strokes of forty samples each. That is more than a page of music
    /// ever carries in practice -- circled accidentals, a few cues, a repeat
    /// crossed out and rewritten -- and it is deliberately past realistic so
    /// the headroom is the thing being measured rather than the typical case.
    func testAHeavilyMarkedPageIsNowhereNearTheDocumentLimit() {
        let drawing = PKDrawing(strokes: (0..<60).map {
            stroke(points: 40, at: CGFloat($0) * 16)
        })
        let bytes = drawing.dataRepresentation().count
        // Recorded so a regression in the format shows up as a number a person
        // can read, not just a pass.
        print("SHARED-INK dense page: \(bytes) bytes")
        XCTAssertTrue(SharedInk.fits([1: drawing.dataRepresentation()]),
                      "a dense page is \(bytes) bytes")
        XCTAssertLessThan(bytes, SharedInk.payloadBudget / 20,
                          "a single page should have at least twenty times "
                          + "the headroom it needs; it is \(bytes) bytes "
                          + "against a budget of \(SharedInk.payloadBudget)")
    }

    /// The case that actually matters: a whole arrangement, marked throughout.
    ///
    /// Twenty pages, each carrying the dense page above. This is the document
    /// the limit applies to.
    func testAWholeMarkedUpArrangementFitsInOneDocument() {
        var pages: [Int: Data] = [:]
        for page in 1...20 {
            pages[page] = PKDrawing(strokes: (0..<60).map {
                stroke(points: 40, at: CGFloat($0) * 16)
            }).dataRepresentation()
        }
        let total = SharedInk.size(of: pages)
        print("SHARED-INK 20 dense pages: \(total) bytes of "
              + "\(SharedInk.payloadBudget)")
        XCTAssertTrue(SharedInk.fits(pages),
                      "twenty dense pages are \(total) bytes, over the "
                      + "\(SharedInk.payloadBudget)-byte budget -- the layout "
                      + "of §4.2 does not hold and ink needs its own document "
                      + "per page")
        XCTAssertTrue(SharedInk.pagesOverBudget(pages).isEmpty)
    }

    /// And when it genuinely does not fit, which pages are reported.
    ///
    /// The budget is what is asserted against, not the raw limit: Firestore
    /// counts field names and the document path too, so a payload that exactly
    /// filled the limit would be a document that fails.
    ///
    /// Two fixtures, because the first one I wrote asserted the wrong answer
    /// and the implementation was right. Three pages of *half the budget plus
    /// one* do not give two that fit: the second already overflows. Kept as its
    /// own case below, because getting that backwards is easy and the number it
    /// produces is the whole point of the function.
    func testPagesThatDoNotFitAreNamedFromTheFrontOfTheScore() {
        // A shade under half each, so pages 1 and 2 fit together and 3 cannot.
        let big = Data(count: SharedInk.payloadBudget / 2 - 1)
        let pages: [Int: Data] = [1: big, 2: big, 3: big]
        XCTAssertFalse(SharedInk.fits(pages))
        // Lowest page first, because that is where a rehearsal starts.
        XCTAssertEqual(SharedInk.pagesOverBudget(pages), [3])
    }

    func testJustOverHalfTheBudgetMeansOnlyOnePageFits() {
        let big = Data(count: SharedInk.payloadBudget / 2 + 1)
        let pages: [Int: Data] = [1: big, 2: big, 3: big]
        XCTAssertEqual(SharedInk.pagesOverBudget(pages), [2, 3])
    }

    /// A page that cannot fit even on its own is skipped, and the pages after
    /// it still go.
    ///
    /// A deliberate choice, and the comment on `pagesOverBudget` used to claim
    /// the opposite -- that the pages which fit are always the ones at the
    /// front. They are not, when a single page is bigger than the whole
    /// budget: dropping every later page as well would lose markup for nothing.
    func testOneEnormousPageDoesNotTakeTheRestOfTheScoreWithIt() {
        let pages: [Int: Data] = [1: Data(count: SharedInk.payloadBudget + 1),
                                  2: Data(count: 32)]
        XCTAssertEqual(SharedInk.pagesOverBudget(pages), [1])
    }

    func testAnEmptyLayerFitsAndCostsNothing() {
        XCTAssertTrue(SharedInk.fits([:]))
        XCTAssertEqual(SharedInk.size(of: [:]), 0)
    }

    // MARK: - the wire form

    func testPagesSurviveTheRoundTripThroughAFirestoreMap() {
        let pages: [Int: Data] = [1: Data([1, 2, 3]), 14: Data([9])]
        XCTAssertEqual(SharedInk.decode(SharedInk.encode(pages)), pages)
    }

    func testAKeyThatIsNotAPageNumberIsDroppedRatherThanFailingTheWholeLayer() {
        // A document written by a later build must not make this one unable to
        // read the pages it does understand.
        let raw: [String: Any] = ["3": Data([7]), "layer": "personal",
                                  "-1": Data([8]), "updatedAt": 0]
        XCTAssertEqual(SharedInk.decode(raw), [3: Data([7])])
    }

    // MARK: - whose marks are drawn

    // MARK: - the page a mark was drawn on

    /// The bug that only appears on the second device.
    ///
    /// A PKDrawing's coordinates are in its canvas's unzoomed space, and this
    /// app lays that canvas out at the page's layout width in points. On one
    /// device the width never changes and nothing is ever wrong; across two, an
    /// iPad's marks arrive on a phone at three times the size and slide off the
    /// page. Invisible until it has shipped, which is why it is a test.
    func testInkDrawnOnAnIPadIsScaledToFitAPhonesPage() {
        // 912pt page on a 13-inch iPad, 358pt on a phone.
        XCTAssertEqual(SharedInk.scale(drawnAt: 912, readAt: 358),
                       358.0 / 912.0, accuracy: 0.0001)
        // And the other direction.
        XCTAssertEqual(SharedInk.scale(drawnAt: 358, readAt: 912),
                       912.0 / 358.0, accuracy: 0.0001)
    }

    func testTheSameSizedPageNeedsNoScaling() {
        XCTAssertEqual(SharedInk.scale(drawnAt: 912, readAt: 912), 1)
    }

    /// A missing or nonsense width draws at 1 rather than vanishing.
    ///
    /// A layer written by a build that did not record its width is ink at
    /// slightly the wrong size, which a person can see and work with. Zero,
    /// NaN or a negative would be ink scaled to nothing, which reads as the
    /// bandmate having drawn nothing at all.
    func testAMissingOrAbsurdWidthDrawsAtLifeSizeRatherThanVanishing() {
        XCTAssertEqual(SharedInk.scale(drawnAt: nil, readAt: 912), 1)
        XCTAssertEqual(SharedInk.scale(drawnAt: 0, readAt: 912), 1)
        XCTAssertEqual(SharedInk.scale(drawnAt: -5, readAt: 912), 1)
        XCTAssertEqual(SharedInk.scale(drawnAt: .nan, readAt: 912), 1)
        XCTAssertEqual(SharedInk.scale(drawnAt: 912, readAt: 0), 1)
        XCTAssertEqual(SharedInk.scale(drawnAt: 912, readAt: .infinity), 1)
    }

    func testMyOwnLayerIsNeverRescaledWhateverWidthWasRecorded() {
        // Rescaling my own layer would move a mark out from under the pencil
        // that just made it.
        let layers = SharedInk.layers(page: 1,
                                      byUser: ["u-son": [1: Data([1])]],
                                      widths: ["u-son": 100],
                                      readAt: 900,
                                      me: "u-son", visibility: .everyone,
                                      participants: ["u-son"])
        XCTAssertEqual(layers.first?.scale, 1)
    }

    func testABandmatesLayerCarriesTheRatioOfTheTwoPages() {
        let layers = SharedInk.layers(page: 1,
                                      byUser: ["u-ali": [1: Data([1])]],
                                      widths: ["u-ali": 450],
                                      readAt: 900,
                                      me: "u-son", visibility: .everyone,
                                      participants: ["u-ali", "u-son"])
        XCTAssertEqual(layers.first?.scale, 2)
    }

    func testEverybodysMarksAreDrawnWithMineOnTopAndEachInTheirOwnColour() {
        let band = ["u-ali", "u-son", "u-zoe"]
        let byUser = Dictionary(uniqueKeysWithValues: band.map {
            ($0, [1: Data([1])])
        })
        let layers = SharedInk.layers(page: 1, byUser: byUser, me: "u-son",
                                      visibility: .everyone, participants: band)
        XCTAssertEqual(layers.map(\.userId), ["u-ali", "u-zoe", "u-son"])
        XCTAssertTrue(layers.last!.isMine)
        XCTAssertEqual(Set(layers.map(\.colour)).count, 3,
                       "three people, three colours")
    }

    func testAnEmptyLayerIsNotDrawnAtAll() {
        // An empty PKDrawing renders as nothing, but it still costs a canvas
        // and a composite per page per person.
        let byUser = ["u-ali": [1: Data()], "u-son": [1: Data([1])]]
        let layers = SharedInk.layers(page: 1, byUser: byUser, me: "u-son",
                                      visibility: .everyone,
                                      participants: ["u-ali", "u-son"])
        XCTAssertEqual(layers.map(\.userId), ["u-son"])
    }

    func testMineOnlyDrawsMineAndOneOtherPersonDrawsThatPerson() {
        let band = ["u-ali", "u-son"]
        let byUser = Dictionary(uniqueKeysWithValues: band.map { ($0, [2: Data([1])]) })
        XCTAssertEqual(SharedInk.layers(page: 2, byUser: byUser, me: "u-son",
                                        visibility: .mine,
                                        participants: band).map(\.userId),
                       ["u-son"])
        XCTAssertEqual(SharedInk.layers(page: 2, byUser: byUser, me: "u-son",
                                        visibility: .only("u-ali"),
                                        participants: band).map(\.userId),
                       ["u-ali"])
    }

    func testAPageNobodyMarkedDrawsNothing() {
        let byUser = ["u-ali": [1: Data([1])]]
        XCTAssertTrue(SharedInk.layers(page: 7, byUser: byUser, me: "u-son",
                                       visibility: .everyone,
                                       participants: ["u-ali", "u-son"]).isEmpty)
    }
}

/// Which shared entry a saved drawing belongs to, read off its key.
///
/// This is the join between the pencil and the cloud, and it is deliberately
/// the ONLY one: the canvas, the annotation controller and the score view know
/// nothing about a set list, and the key a drawing is saved under already
/// carries everything a push needs (design/FIREBASE.md §6.3).
///
/// It has to be strict in one direction and forgiving in the other: almost
/// every save in this app is a local arrangement that must never be pushed
/// anywhere, so anything not positively recognised as a shared entry's page
/// returns nil.
final class SharedEntryKeyTests: XCTestCase {

    func testASharedEntrysPageIsRecognisedWithItsEntryAndPage() {
        let namespace = SharedEntryCopies.inkNamespace(entryId: "e42")
        let key = "\(namespace)/01VERSIONID/p3"
        let found = SharedEntryCopies.entryAndPage(forDrawingKey: key)
        XCTAssertEqual(found?.entry, "e42")
        XCTAssertEqual(found?.page, 3)
    }

    /// The case that matters most: a local arrangement's markup must never be
    /// pushed to a set list. Every one of these is a key this app really
    /// writes.
    func testALocalArrangementsKeyIsNotAnEntryAndIsNeverPushed() {
        for key in ["01SCOREUID/01VERSIONID/p0",
                    "under-paris-skies-accordion-solo/01VERSIONID/p2",
                    "01SCOREUID/01VERSIONID",
                    ""] {
            XCTAssertNil(SharedEntryCopies.entryAndPage(forDrawingKey: key), key)
        }
    }

    func testAKeyThatIsShapedWrongIsRefusedRatherThanGuessedAt() {
        for key in ["shared/e1/p3",                  // no version
                    "shared/e1/v1/p3/extra",         // too deep
                    "shared/e1/v1/3",                // no p
                    "shared/e1/v1/page3",
                    "shared//v1/p3",                 // no entry
                    "shared/e1/v1/pX"] {
            XCTAssertNil(SharedEntryCopies.entryAndPage(forDrawingKey: key), key)
        }
    }

    func testPageZeroIsAPageBecauseTheFirstPageIsIndexZero() {
        XCTAssertEqual(SharedEntryCopies.entryAndPage(forDrawingKey: "shared/e1/v1/p0")?.page, 0)
    }

    func testTheNamespaceSaysWhetherMarkupBelongsToASetListOrToMe() {
        XCTAssertTrue(SharedEntryCopies.isShared(
            namespace: SharedEntryCopies.inkNamespace(entryId: "e1")))
        XCTAssertFalse(SharedEntryCopies.isShared(namespace: "01SCOREUID"))
        XCTAssertFalse(SharedEntryCopies.isShared(namespace: "shared-notes"))
    }

    /// The band's markup and my own notes on my own copy are different things,
    /// filed apart. One key for both would publish the private one.
    func testASharedEntryAndMyOwnCopyOfTheSameTuneDoNotShareAKey() {
        XCTAssertNotEqual(SharedEntryCopies.inkNamespace(entryId: "e1"), "01SCOREUID")
    }

    // MARK: - where this device put its copy

    func testAnEntrysLocalCopyIsRememberedAndCanBeForgotten() {
        let defaults = UserDefaults(suiteName: "shared-entry-copies-test")!
        defaults.removePersistentDomain(forName: "shared-entry-copies-test")
        let copies = SharedEntryCopies(defaults: defaults)
        XCTAssertNil(copies.localSlug(forEntry: "e1"))
        copies.remember(entryId: "e1", localSlug: "some-tune")
        XCTAssertEqual(copies.localSlug(forEntry: "e1"), "some-tune")
        copies.forget(entryId: "e1")
        XCTAssertNil(copies.localSlug(forEntry: "e1"))
    }
}
