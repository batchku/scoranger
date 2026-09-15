import Foundation

/// The marks a reader can size, move and put back, and what each is called on
/// the way to the engine.
///
/// One table rather than a switch in each caller. `adjust-element`,
/// `move-element` and `duplicate-element` all address an element as
/// part + kind + measure + ordinal, and the kind they take is a STRING of the
/// engine's own spelling -- which is not the MEI tag the app selects by
/// (`dynam` against `dynamic`, `artic` against `articulation`). Every place
/// that crossed the two used to spell it out again.
enum AddedMark {

    /// In the order the adjust row offers them, and the order the engine's
    /// ELEMENT_KINDS lists them.
    static let kinds: [ScoreElementKind] = [.harm, .dynam, .text, .fermata,
                                            .articulation]

    /// The engine's name for this kind, or nil when the engine cannot address
    /// it at all -- a note, a slur, a clef.
    static func engineKind(_ kind: ScoreElementKind) -> String? {
        switch kind {
        case .harm:         return "harm"
        case .dynam:        return "dynamic"
        case .text:         return "text"
        case .fermata:      return "fermata"
        case .articulation: return "articulation"
        default:            return nil
        }
    }

    /// What to call it in a sentence a reader sees.
    static func noun(_ kind: ScoreElementKind) -> String {
        switch kind {
        case .harm:         return "chord symbol"
        case .dynam:        return "dynamic"
        case .text:         return "text mark"
        case .fermata:      return "fermata"
        case .articulation: return "articulation"
        default:            return "element"
        }
    }

    /// Whether the mark hangs off a NOTE rather than sitting at an offset of
    /// its own. It decides what a destination has to be: a note-attached mark
    /// can only land where a note starts, and `ops.move_element` refuses -- and
    /// lists the bar's onsets -- when nothing does.
    static func isNoteAttached(_ kind: ScoreElementKind) -> Bool {
        kind == .fermata || kind == .articulation
    }

    /// Which reading of the notation carries this kind's stored size and
    /// offset. Nil for kinds `ChordAdjustments` does not draw.
    static func adjustmentKind(_ kind: ScoreElementKind) -> ChordAdjustments.Kind? {
        switch kind {
        case .harm:         return .harm
        case .dynam:        return .dynamic
        case .text:         return .text
        case .fermata:      return .fermata
        case .articulation: return .articulation
        default:            return nil
        }
    }

    /// How this kind's size is counted and said.
    ///
    /// A CHORD SYMBOL keeps the point ladder it shipped with: the part-wide
    /// default beside it is a point value, the two have to be comparable, and
    /// every chord symbol already nudged in a score carries points.
    /// Everything else is RELATIVE to the engraved default, which is the
    /// decided answer (BACKLOG.md, "Worth deciding before building"): a reader
    /// asking for a bigger fermata means bigger than the ones around it, and a
    /// page later engraved at another scale must keep the proportion.
    static func sizeMetric(_ kind: ScoreElementKind) -> ChordAdjustSession.SizeMetric {
        kind == .harm ? .points : .relative
    }
}
