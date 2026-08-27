import Foundation

/// One element's worth of nudging and resizing, held until it is committed.
///
/// The spec's rule (docs/size-and-position-spec.md, "Committing"): each tap
/// must NOT be an op. Taps accumulate here and commit once, when the reader
/// leaves the element — deselects it, selects another, leaves the score, or
/// stops for three seconds. Committing per tap would write a version per tap,
/// and the notation is versioned, so a single nudge would cost forty of them.
///
/// Preview is free: `ChordAdjustments` already applies size and offset in the
/// app, so pending values draw locally and only the commit reaches the engine.
struct ChordAdjustSession: Equatable {

    enum Direction { case up, down, left, right }
    enum SizeStep { case bigger, smaller }

    /// Half a staff space, in MusicXML tenths. Five is exact in every unit
    /// this chain uses: 0.5 staff space, 5 tenths, 1 MEI half-space. Nothing
    /// rounds, which is why it is not 4 or 6.
    static let stepTenths: Int = 5

    /// Clamps, in tenths. A symbol that could travel further would wander into
    /// the system above and read as belonging to it.
    static let maxVerticalTenths: Int = 40    // ±4 staff spaces
    static let maxHorizontalTenths: Int = 20  // ±2 staff spaces

    /// Clean point sizes rather than a multiplier. A multiplier writes 13.5 pt
    /// and then 15.19 pt into the notation and makes "put it back" impossible
    /// to hit exactly.
    static let sizeLadder: [Int] = [8, 9, 10, 11, 12, 14, 16, 18, 20, 24]

    /// What is already in the notation.
    private let committedSize: Int
    private let committedDX: Int
    private let committedDY: Int

    /// What the reader has asked for but not yet spent a version on.
    private(set) var pending: Pending

    struct Pending: Equatable {
        var size: Int
        var dx: Int
        var dy: Int
        var isReset: Bool = false
    }

    /// The absolute values the engine will be given.
    struct Commit: Equatable {
        var size: Int?
        var offsetX: Int?
        var offsetY: Int?
        var reset: Bool
    }

    init(size: Int, committedDX: Int = 0, committedDY: Int = 0) {
        self.committedSize = size
        self.committedDX = committedDX
        self.committedDY = committedDY
        self.pending = Pending(size: size, dx: 0, dy: 0)
    }

    /// Offset including what the notation already carries — what the clamp is
    /// measured against, so a symbol nudged to the limit yesterday cannot be
    /// pushed past it today.
    var total: (dx: Int, dy: Int) {
        (committedDX + pending.dx, committedDY + pending.dy)
    }

    var hasPendingChange: Bool {
        pending.isReset || pending.dx != 0 || pending.dy != 0 || pending.size != committedSize
    }

    // MARK: - Position

    func canNudge(_ direction: Direction) -> Bool {
        let (dx, dy) = total
        switch direction {
        case .up:    return dy + Self.stepTenths <= Self.maxVerticalTenths
        case .down:  return dy - Self.stepTenths >= -Self.maxVerticalTenths
        case .right: return dx + Self.stepTenths <= Self.maxHorizontalTenths
        case .left:  return dx - Self.stepTenths >= -Self.maxHorizontalTenths
        }
    }

    /// MusicXML `relative-y` measures UP, so down is negative.
    mutating func nudge(_ direction: Direction) {
        guard canNudge(direction) else { return }
        pending.isReset = false
        switch direction {
        case .up:    pending.dy += Self.stepTenths
        case .down:  pending.dy -= Self.stepTenths
        case .right: pending.dx += Self.stepTenths
        case .left:  pending.dx -= Self.stepTenths
        }
    }

    // MARK: - Size

    func canResize(_ step: SizeStep) -> Bool {
        nextRung(from: pending.size, step: step) != nil
    }

    mutating func resize(_ step: SizeStep) {
        guard let next = nextRung(from: pending.size, step: step) else { return }
        pending.isReset = false
        pending.size = next
    }

    /// The next rung, or nil at the ends. A size that is not on the ladder --
    /// set by chat, or by another program -- steps to the nearest rung in the
    /// asked-for direction rather than being snapped on arrival, which would
    /// change a value the reader never touched.
    private func nextRung(from size: Int, step: SizeStep) -> Int? {
        switch step {
        case .bigger: return Self.sizeLadder.first { $0 > size }
        case .smaller: return Self.sizeLadder.last { $0 < size }
        }
    }

    // MARK: - Undoing

    /// Discard everything uncommitted. Not a change; nothing reaches the engine.
    mutating func revert() {
        pending = Pending(size: committedSize, dx: 0, dy: 0)
    }

    /// Back to the inherited size and no offset. This IS a change and commits,
    /// unless the element was already untouched.
    mutating func reset() {
        guard committedDX != 0 || committedDY != 0
                || committedSize != Self.defaultSize else {
            pending = Pending(size: committedSize, dx: 0, dy: 0)
            return
        }
        pending = Pending(size: Self.defaultSize,
                          dx: -committedDX, dy: -committedDY, isReset: true)
    }

    /// The size an untouched chord symbol engraves at, mirroring
    /// `ChordAdjustments.defaultChordPoints`.
    static let defaultSize = 12

    // MARK: - Committing

    /// The one op this session produces, or nil when there is nothing to write.
    /// An empty commit would still cost a version.
    mutating func commit() -> Commit? {
        guard hasPendingChange else { return nil }
        if pending.isReset { return Commit(size: nil, offsetX: nil, offsetY: nil, reset: true) }
        let (dx, dy) = total
        return Commit(size: pending.size,
                      offsetX: dx,
                      offsetY: dy,
                      reset: false)
    }

    // MARK: - What the chip says

    static func staffSpaces(fromTenths tenths: Int) -> Double {
        Double(tenths) / 10.0
    }

    /// `0.5 sp up · 14 pt`, or nil when nothing is pending.
    var pendingDescription: String? {
        guard hasPendingChange else { return nil }
        if pending.isReset { return "reset" }
        var parts: [String] = []
        if pending.dy != 0 {
            parts.append("\(Self.spaces(abs(pending.dy))) sp \(pending.dy > 0 ? "up" : "down")")
        }
        if pending.dx != 0 {
            parts.append("\(Self.spaces(abs(pending.dx))) sp \(pending.dx > 0 ? "right" : "left")")
        }
        parts.append("\(pending.size) pt")
        return parts.joined(separator: " · ")
    }

    /// `0.5`, `1`, `1.5` — never `1.0`, which reads as a measurement nobody made.
    private static func spaces(_ tenths: Int) -> String {
        let value = staffSpaces(fromTenths: tenths)
        return value == value.rounded() ? String(Int(value)) : String(value)
    }
}
