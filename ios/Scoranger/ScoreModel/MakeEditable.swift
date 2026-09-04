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
        guard pages > 0 else { return ("reading the score…", nil) }
        let current = min(max(page, 1), pages)
        let behind = Double(current - 1) / Double(pages)
        return ("reading page \(current) of \(pages)",
                min(max(behind, convertingFloor), convertingCeiling))
    }

    static func control(busy: Bool, stage: String?, fraction: Double?) -> OMRControl {
        guard busy else {
            return OMRControl(isOn: false, detail: offer, fraction: nil,
                              showsSpinner: false, acceptsTap: true)
        }
        // The stage is the OMR job's own word for what it is doing --
        // "uploading…", "converting…", "importing…". It is more use than
        // "reading…" was, and it is the only sign the reader gets that the
        // wait is a wait rather than a failure.
        let detail = (stage?.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 } ?? "reading…"
        return OMRControl(isOn: true, detail: detail, fraction: fraction,
                          showsSpinner: fraction == nil, acceptsTap: false)
    }
}
