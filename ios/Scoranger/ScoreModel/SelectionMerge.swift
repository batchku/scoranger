import CoreGraphics

/// One drawn selection mark.
///
/// A box per caught element, until a whole bar is caught -- see
/// `SelectionMerge`, which is the only thing that makes one of these carry a
/// `.measure` kind.
struct SelectionBox: Equatable {
    let frame: CGRect
    let kind: ScoreElementKind
}

/// When a selection stops being a scatter of boxes and becomes a bar.
///
/// IPHONE_0.6.14 §13, and the reason it exists is in the frame that prompted
/// it: a bar selected at fit drew ten overlapping note boxes, and multiplied
/// fills COMPOUND where they overlap -- two layers of 22% read as 39%, three
/// as 53%. What should have been the lightest mark on the page was the
/// heaviest.
///
/// So a complete bar is drawn ONCE. The three ways of getting that wrong are
/// each a bug this project has already had, and each is ruled out here:
///
/// - **Never the measure element's own frame.** A `<measure>` in MEI spans
///   every staff of the system, so drawing it lights the whole system for a
///   selection on one staff -- bug #9, where lassoing three notes lit the bar,
///   and #10a, where tapping empty space selected it. The union is of the
///   MEMBERS' own frames and reaches exactly as far as they do.
/// - **Never one rectangle across bars.** Two complete bars are two marks.
///   The reader is being told which bars, and one rectangle over both says
///   something else.
/// - **Never additive.** The union REPLACES the member boxes. Drawn over them
///   it would be a fourth layer on top of the compounding it exists to stop.
///
/// A partly-selected bar keeps its individual boxes: it is not a bar.
enum SelectionMerge {

    /// One selected element: where it is, and what it is.
    struct Member: Equatable {
        let address: ScoreAddress
        let frame: CGRect
    }

    /// A bar on a staff -- the unit a mark is merged over.
    struct Key: Hashable {
        let measure: Int
        let staff: Int
    }

    /// What to draw for a page's worth of selected elements.
    ///
    /// `population` is how many selectable addresses each bar-on-a-staff holds
    /// in the document, which is what "every one of them is selected" is
    /// measured against. A key missing from it is a bar nothing is known about,
    /// and an unknown bar is never merged -- silence is not completeness.
    static func boxes(selected: [Member], population: [Key: Int]) -> [SelectionBox] {
        var order: [Key] = []
        var groups: [Key: [Member]] = [:]
        for member in selected {
            let key = Key(measure: member.address.measure,
                          staff: member.address.staff)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(member)
        }
        return order.flatMap { key -> [SelectionBox] in
            let members = groups[key] ?? []
            guard let whole = population[key], whole > 0,
                  distinct(members) >= whole,
                  let union = union(of: members) else {
                return members.map { SelectionBox(frame: $0.frame, kind: $0.address.kind) }
            }
            return [SelectionBox(frame: union, kind: .measure)]
        }
    }

    /// Counted by ADDRESS, not by element: the same address arriving twice --
    /// a lasso that added what a tap had already caught -- must not add up to
    /// a bar that is not complete.
    private static func distinct(_ members: [Member]) -> Int {
        Set(members.map(\.address)).count
    }

    private static func union(of members: [Member]) -> CGRect? {
        members.map(\.frame).reduce(nil) { total, frame in
            total.map { $0.union(frame) } ?? frame
        }
    }
}
