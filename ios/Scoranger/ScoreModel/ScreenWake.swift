import Foundation

/// Whether the screen should be held awake.
///
/// Ali: the iPad dims and locks while he is playing, because a musician reading
/// a score touches the glass once a page and the system counts that as idle.
/// A dark screen mid-tune is the app failing at the one thing it is for.
///
/// So the idle timer is disabled — but only where reading is happening, which
/// is the whole design of this. `isIdleTimerDisabled` is a property of the
/// APPLICATION, not of a view, so anything that sets it without something else
/// clearing it holds the screen awake over the library, over Settings, and for
/// as long as the app stays running. That is a battery bug rather than a
/// feature, and it is the failure mode this type exists to prevent: one rule,
/// stated once, over the three facts that decide it.
///
/// The scene phase is one of those facts for a reason that is not obvious. The
/// idle timer means nothing while the app is in the background, so the flag
/// could simply be left set — but leaving it set means it is set for whatever
/// the reader does NEXT, and a flag nobody clears is exactly how the library
/// ends up holding the screen awake. It is cleared on the way out and applied
/// again on the way back, so the app's claim on the screen never outlives the
/// app being in front of somebody.
enum ScreenWake {

    /// The three facts, so the rule reads as one sentence at its call site.
    struct Conditions: Equatable {
        /// A score is open and being read.
        var readingScore: Bool
        /// The transport is running, which is reading whether or not anybody
        /// is looking at the page.
        var playing: Bool
        /// The app is frontmost. Not `scenePhase == .active` as a String: the
        /// caller converts, and this stays testable without SwiftUI.
        var appActive: Bool
    }

    /// Hold the screen awake?
    ///
    /// Playing counts on its own. It cannot happen with no score open today,
    /// but the rule does not lean on that: sound coming out of the device is
    /// reason enough not to lock it, and if playback ever outlives the reader
    /// this answer stays right.
    static func shouldStayLit(_ conditions: Conditions) -> Bool {
        guard conditions.appActive else { return false }
        return conditions.readingScore || conditions.playing
    }

    static func shouldStayLit(readingScore: Bool, playing: Bool,
                              appActive: Bool) -> Bool {
        shouldStayLit(Conditions(readingScore: readingScore, playing: playing,
                                 appActive: appActive))
    }
}
