import XCTest

/// #42: the empty state flashed on every launch, on a device full of music.
final class LibraryListStateTests: XCTestCase {

    /// The regression, stated: before the manifest arrives nothing is known,
    /// so "there is no music" may not be claimed.
    func testBeforeTheLibraryLoadsItIsLoadingNotEmpty() {
        XCTAssertEqual(LibraryModel.listState(loaded: false, rows: 0,
                                              pendingImports: 0, isFiltered: false),
                       .loading)
    }

    /// ...and not even when a search is on, which is the same unknown.
    func testALoadingLibraryIsNeverNoMatches() {
        XCTAssertEqual(LibraryModel.listState(loaded: false, rows: 0,
                                              pendingImports: 0, isFiltered: true),
                       .loading)
    }

    func testALoadedLibraryWithNothingInItIsEmpty() {
        XCTAssertEqual(LibraryModel.listState(loaded: true, rows: 0,
                                              pendingImports: 0, isFiltered: false),
                       .empty)
    }

    func testALoadedLibraryWithNoMatchesSaysSo() {
        XCTAssertEqual(LibraryModel.listState(loaded: true, rows: 0,
                                              pendingImports: 0, isFiltered: true),
                       .noMatches)
    }

    func testRowsAreRowsWhicheverWayTheyArrived() {
        XCTAssertEqual(LibraryModel.listState(loaded: true, rows: 3,
                                              pendingImports: 0, isFiltered: false),
                       .rows)
        XCTAssertEqual(LibraryModel.listState(loaded: false, rows: 3,
                                              pendingImports: 0, isFiltered: false),
                       .rows)
    }

    /// An import in flight is content: its row is already on screen, so the
    /// list is not empty even before the manifest catches up.
    func testAnImportInFlightIsNotAnEmptyLibrary() {
        XCTAssertEqual(LibraryModel.listState(loaded: true, rows: 0,
                                              pendingImports: 1, isFiltered: false),
                       .rows)
        XCTAssertEqual(LibraryModel.listState(loaded: false, rows: 0,
                                              pendingImports: 1, isFiltered: false),
                       .rows)
    }

    /// The property that matters: for EVERY way a populated library can be
    /// described, the empty state is unreachable.
    func testAPopulatedLibraryCanNeverShowTheEmptyState() {
        for loaded in [true, false] {
            for filtered in [true, false] {
                for pending in [0, 2] {
                    let state = LibraryModel.listState(loaded: loaded, rows: 5,
                                                       pendingImports: pending,
                                                       isFiltered: filtered)
                    XCTAssertEqual(state, .rows,
                                   "loaded=\(loaded) filtered=\(filtered) pending=\(pending)")
                }
            }
        }
    }
}
