import Foundation

/// What the "Make editable" control shows, and whether it accepts a tap.
///
/// The control was a row: a title, the words "run OMR" on its trailing edge,
/// and a tap that popped the screen. Three things were wrong with it. It did
/// not read as pressable -- every other row on that screen leads somewhere,
/// and this one performs. Pressing it looked like nothing happened, because
/// the screen it was on went away and the work carried on somewhere else. And
/// the only progress it ever showed was the word "reading…", visible solely if
/// the reader came back to the screen they had just been thrown out of.
///
/// So it is a switch, like Performance mode above it, and it stays on the
/// screen and reports what OMR is doing. It is a one-way switch: OMR cannot be
/// un-run, and when it succeeds the arrangement stops being a scan and the row
/// goes with it. Failure turns it back off, and the notice says why.
struct OMRControl: Equatable {
    /// Whether the switch is drawn on.
    var isOn: Bool
    /// The line under the title: the stage while it runs, the offer before.
    var detail: String
    /// A determinate bar when the stage reports one (the upload does), and a
    /// spinner for the stages that cannot.
    var fraction: Double?
    var showsSpinner: Bool
    /// A switch already on is inert: a second tap must not start a second run
    /// on the same page.
    var acceptsTap: Bool
}

enum MakeEditable {

    static let offer = "Reads the page into notation. The PDF stays as it is."

    /// The words and the bar for the CONVERTING stage, in one place because
    /// three surfaces draw them now: the Make editable row, the library's
    /// import row, and the top bar's chip.
    ///
    /// `page` is the sheet Audiveris is WORKING ON, not the number it has
    /// finished, so the pages behind it are `page - 1`. Read as a count of
    /// finished pages it put the bar at 1.0 and the words at "reading page N
    /// of N" from the first poll of the job -- reproduced end to end against
    /// the real service and the real Audiveris on an 8-page score: every one
    /// of the 40 polls over 78 seconds of converting drew a full bar. The
    /// service's own half of that is `SHEET_MARK` in omr-service/server.py,
    /// which was matching the sheet LIST Audiveris prints in its first second.
    ///
    /// The bar never fills HERE, whatever arrives. Filling it is what `done`
    /// means, and a bar that is full while the work runs is the same lie
    /// however it got that way -- including from a service still reporting the
    /// old numbers, which no client-side arithmetic can tell apart from a job
    /// genuinely on its last page.
    static let convertingCeiling = 0.95
    static let convertingFloor = 0.02

    static func converting(page: Int, pages: Int) -> (stage: String, fraction: Double?) {
        // No page count: Audiveris is reading something whose length we never
        // learned, and a bar with no denominator is a spinner.
        guard pages > 0 else { return ("reading…", nil) }
        let current = min(max(page, 1), pages)
        let behind = Double(current - 1) / Double(pages)
        // "reading p. 8 / 12". Ali photographed the top bar saying "page 1 of
        // 2" while the canvas, on the same screen in two-page view, said
        // "pp. 1-2 / 2" -- two position readouts contradicting each other.
        // They were never about the same thing: one is where the reader is,
        // the other is which sheet Audiveris is on. So this one names the
        // ACTION and counts in the same grammar the page counter uses
        // (`ScorePosition.pageLabel`), and the pair can be read together
        // without one denying the other.
        //
        // The verb was dropped once, for width: "reading page 8 of 12"
        // compressed to "reading page 8…" in the chip. "reading p. 8 / 12" is
        // eighteen characters, the same as "waiting (1 ahead)…", which is what
        // `ScoreBarLayout.omrWidth` was already sized for.
        return ("reading p. \(current) / \(pages)",
                min(max(behind, convertingFloor), convertingCeiling))
    }

    /// The switch, from THIS ARRANGEMENT'S transcription and nothing else.
    ///
    /// `status` is `OMRQueue.status(ofArrangement:)` -- the single answer the
    /// chip, the Convert panel and the transport also read. The switch used to
    /// be built from an app-wide `busy` Bool and the chip from the same one,
    /// which is how a score could show a progress bar with its own Make
    /// editable off. One value, one answer, nothing to drift.
    ///
    /// A job WAITING its turn reads as on: the reader asked for it, and a
    /// switch that flicks back off until the queue reaches it would look like
    /// the tap was lost.
    static func control(status: OMRStatus?) -> OMRControl {
        guard let status else {
            return OMRControl(isOn: false, detail: offer, fraction: nil,
                              showsSpinner: false, acceptsTap: true)
        }
        // The stage is the OMR job's own word for what it is doing --
        // "uploading…", "converting…", "importing…" -- or its place in the
        // queue when it has not started. It is more use than "reading…" was,
        // and it is the only sign the reader gets that the wait is a wait
        // rather than a failure.
        let detail = detailText(status)
        return OMRControl(isOn: true, detail: detail, fraction: status.fraction,
                          showsSpinner: status.showsSpinner, acceptsTap: false)
    }

    /// The words, in one place, so the switch and the chip say the same thing.
    static func detailText(_ status: OMRStatus) -> String {
        let said = status.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return said.isEmpty ? "reading…" : said
    }
}

/// The OFFER, as a panel state (design/redesign-0.8/notebook-spec.html SC13).
///
/// Until 0.8.2 the only way to ask for OMR was a switch among the rows of
/// More, and the only sign it was running was a chip on the top bar. Both
/// were reachable only by a reader who already knew to look: a scan opened
/// as a PDF and said nothing about what it could become. SC13 makes the
/// question a panel state that opens WITH the scan, answered by Convert or
/// by Read as is -- and More keeps a row that opens the same state again, so
/// answering "read as is" costs nothing permanent.
///
/// The words are here rather than in the view because the offer, the More
/// row's value and the running report have to agree, and three copies of a
/// sentence is how they stop agreeing.
enum ConvertOffer {
    static let question = "Convert to notation?"
    /// What converting buys, and what it costs -- which is nothing, because
    /// the scan stays as its own version.
    static let reason = "So it can be arranged, transposed and played. "
        + "The scan stays as its own version either way, so you can compare them."
    /// Said BEFORE the reader answers, not after: an OMR draft with wrong ties
    /// is a surprise only to someone who was not told.
    static let caution = "Converted scores are drafts: expect wrong ties, "
        + "dynamics and articulations, and check the part names. "
        + "Ask in chat to fix them."
    static let convert = "Convert"
    static let readAsIs = "Read as is"
    /// The line under the progress: the wait does not hold the reader.
    static let keepReading = "Keep reading; the notation version opens when it is done."

    /// Whether opening this arrangement should put the offer on screen.
    ///
    /// `answered` is the set of slugs whose offer has already had an answer.
    /// Either answer counts: a reader who said "read as is" is not asked
    /// again by opening the same scan, and More's row is how they change
    /// their mind.
    static func opens(artifact: ScoreArtifact.Kind, slug: String,
                      answered: Set<String>, status: OMRStatus?) -> Bool {
        guard ScoreArtifact.canBeMadeEditable(artifact) else { return false }
        guard status == nil else { return false }
        guard !slug.isEmpty else { return false }
        return !answered.contains(slug)
    }

    /// What More's row says on its trailing edge, so the row is a summary and
    /// not a bare label (L34).
    /// What the panel is headed by. A job that has not started yet is not
    /// converting, and saying it is would be the same lie the app-wide busy
    /// flag told.
    static func heading(_ status: OMRStatus?) -> String {
        switch status {
        case .none:      return question
        case .waiting:   return "In the queue"
        case .running:   return "Converting"
        }
    }

    static func rowValue(status: OMRStatus?) -> String {
        guard let status else { return "not yet" }
        return MakeEditable.detailText(status)
    }
}
