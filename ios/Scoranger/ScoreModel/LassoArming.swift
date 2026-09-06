import Foundation

/// Whether one finger draws a loop, and for how long.
///
/// IPHONE_0.6.14 §9.3. Tapping needs no mode; a lasso does. A one-finger drag
/// is already pan and page turn, and this app separates inputs by MODE rather
/// than by a guess at timing or distance -- the rule that keeps the Pencil's
/// lasso and the Pencil's page turn apart (§6.1). A phone has no Pencil, so
/// the finger needs the arrangement the Pencil never did.
///
/// Three states rather than a Bool, because "armed for one" and "armed until I
/// say otherwise" behave differently on the very next gesture and a reader who
/// cannot tell which they are in loses their next pan to a loop.
enum LassoArming: Equatable {
    /// The finger pans, taps and turns as usual.
    case off
    /// The next loop, and then off again. The common case is one selection.
    case once
    /// Several loops, until it is turned off. Tapped twice.
    case latched

    var isArmed: Bool { self != .off }

    /// The control's whole behaviour: off -> once -> latched -> off.
    ///
    /// A second tap LATCHES rather than disarming, so "several in a row" needs
    /// no second control; a third turns it off, so the sequence always has a
    /// way out at the same place the reader's thumb already is.
    var tapped: LassoArming {
        switch self {
        case .off:     return .once
        case .once:    return .latched
        case .latched: return .off
        }
    }

    /// A loop landed. Unlatched, that is the end of the mode.
    var afterOneLoop: LassoArming { self == .once ? .off : self }

    /// What the control says it will do, which is not the same in the two
    /// armed states and is the only thing on screen that says so.
    var label: String {
        switch self {
        case .off:     return "Select"
        case .once:    return "Select: on for one selection"
        case .latched: return "Select: keep on"
        }
    }
}
