import Foundation

/// The name proposed for a set list made from checked pieces
/// (REDESIGN_BRIEF_0.8 §7.5). Four rules, first match wins; every input is
/// the selected pieces in the list's sort order.
///
///   1. TITLES    two or three pieces whose joined names fit the budget:
///                "Autumn Leaves, Sous le ciel"
///   2. COMPOSER  every piece has the same non-empty composer:
///                "Piazzolla, 7 pieces"
///   3. WEEKDAY   "Thursday set" -- what a gigging musician writes
///   4. DEDUPE    a taken name gets " 2", " 3", … until it is free
///
/// The budget of 34 characters is measured, not chosen: a set list row
/// reserves `rowTwoControlInset` for share and ☰, leaving 253pt of title at
/// 13.5pt, which is 34 characters before truncation. A generated name that
/// truncates in the row it is generated into is the wrong default.
///
/// Composer equality is STRICT -- trimmed, case-folded, punctuation stripped,
/// compared whole. OMR yields "J.S. Bach", "Johann Sebastian Bach" and
/// "BACH, J.S." for one person; rule 2 not firing costs a weekday, firing
/// wrongly costs a lie.
///
/// Rule 3 always produces a name and rule 4 always makes it unique, so there
/// is no generic fallback; a path to one would be a bug.
enum SetlistNaming {

    struct Piece: Equatable {
        var title: String
        var composer: String?
        init(title: String, composer: String? = nil) {
            self.title = title; self.composer = composer
        }
    }

    static let budget = 34

    static func name(for pieces: [Piece], taken: Set<String> = [],
                     on date: Date = Date(), calendar: Calendar = .current) -> String {
        dedupe(base(for: pieces, on: date, calendar: calendar), taken: taken)
    }

    /// Rules 1 to 3.
    static func base(for pieces: [Piece], on date: Date = Date(),
                     calendar: Calendar = .current) -> String {
        let titles = pieces.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if (2...3).contains(titles.count) {
            let joined = titles.joined(separator: ", ")
            if joined.count <= budget { return joined }
        }
        let composers = pieces.map { normalisedComposer($0.composer) }
        if let first = composers.first, !first.isEmpty, composers.allSatisfy({ $0 == first }),
           let written = pieces.first?.composer?.trimmingCharacters(in: .whitespacesAndNewlines) {
            let count = pieces.count == 1 ? "1 piece" : "\(pieces.count) pieces"
            return "\(written), \(count)"
        }
        return "\(weekday(on: date, calendar: calendar)) set"
    }

    /// Rule 4.
    static func dedupe(_ base: String, taken: Set<String>) -> String {
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    /// Case, diacritics, punctuation and spacing are noise ("J.S. Bach",
    /// "js bach", "J. S. Bach" are one string); a different spelling is not.
    static func normalisedComposer(_ composer: String?) -> String {
        guard let composer else { return "" }
        let folded = composer.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let kept = folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(kept))
    }

    static func weekday(on date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? Locale.current
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }
}
