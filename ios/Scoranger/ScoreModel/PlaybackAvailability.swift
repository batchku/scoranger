import Foundation

/// Why the transport cannot play what is on screen, and what to do about it.
///
/// This replaced a bare `String?`. The string was accurate -- "Run OMR to play
/// this arrangement" -- and inert: it named the remedy without offering it, in
/// a transport whose buttons it had just replaced. A reader whose whole library
/// is imported PDFs saw that line on every score and had nowhere to tap.
///
/// So a reason now carries its remedy. The cases that CAN be fixed from here
/// say what the fix is called, and the transport draws a button instead of a
/// sentence.
enum PlaybackAvailability: Equatable {
    /// Notation, on-device engine: the transport plays.
    case available
    /// A scan. There is no notation behind it until OMR has run -- the same
    /// reason selection and chat editing are unavailable on one.
    case needsTranscription
    /// OMR is running on this arrangement right now.
    case transcribing
    /// `playback` is a bridge op and `scor serve` has no route for it.
    case needsLocalEngine

    /// The whole rule, in one place and with no view or app state around it.
    ///
    /// Derived, never stored: the transport must come back on its own the
    /// moment OMR adds a notation version, without the reader closing and
    /// reopening the arrangement. A cached answer is how that regresses.
    static func of(artifact: ScoreArtifact.Kind,
                   omrBusy: Bool,
                   localEngine: Bool) -> PlaybackAvailability {
        // Transcribing is checked first: while OMR runs, the artifact on
        // screen is STILL the scan, and asking about the artifact alone would
        // offer the button again and start a second run on the same page.
        if artifact == .scan { return omrBusy ? .transcribing : .needsTranscription }
        if !localEngine { return .needsLocalEngine }
        return .available
    }

    var canPlay: Bool { self == .available }

    /// What the transport says. Empty when it is playing instead.
    var message: String {
        switch self {
        case .available:          return ""
        case .needsTranscription: return "This is a scan"
        // Said before the wait, not after it. OMR on a dense or oversized page
        // is imperfect by nature, and a reader told afterwards that their
        // notation is a draft has already been misled once.
        case .transcribing:       return "Transcribing… the result is a draft to correct"
        case .needsLocalEngine:   return "Playback needs the on-device engine"
        }
    }

    /// The button's title, when there is something to press. Nil while a case
    /// cannot be resolved from the transport.
    var actionTitle: String? {
        switch self {
        case .needsTranscription: return "Run OMR to play"
        case .needsLocalEngine:   return "Open Settings"
        case .available, .transcribing: return nil
        }
    }

    /// Whether the reader should be told the outcome is a draft. True while it
    /// runs, and true before it starts -- the honesty belongs on the button,
    /// not only on the spinner.
    var warnsItIsADraft: Bool {
        self == .needsTranscription || self == .transcribing
    }

    var identifier: String {
        switch self {
        case .available:          return "transport-available"
        case .needsTranscription: return "transport-needs-omr"
        case .transcribing:       return "transport-transcribing"
        case .needsLocalEngine:   return "transport-needs-local-engine"
        }
    }
}
