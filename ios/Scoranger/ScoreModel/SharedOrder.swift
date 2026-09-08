import Foundation

/// The running order of a shared setlist, as a key per entry rather than an
/// array on the parent.
///
/// design/FIREBASE.md §6.5. The running order is the thing two people are most
/// likely to touch at once, and an array on the setlist document is the shape
/// that guarantees one of them loses everything: two clients each write the
/// whole array, and last-writer-wins silently discards the other's move.
///
/// So each entry carries its own `order` key, and moving one entry is a
/// one-field write to one document. Two people moving DIFFERENT entries both
/// succeed, with no merge function and no coordination. Two people moving the
/// SAME entry conflict, the later write wins, and that is both correct and
/// unsurprising -- it is what "we both dragged the same tune" should do.
///
/// The keys are strings compared lexicographically, not doubles. A double
/// between two neighbours runs out of mantissa after about fifty consecutive
/// insertions in the same gap, and "the order stopped being editable" is a
/// worse failure than anything this replaces. A string can always be extended.
///
/// Piece ordering and private setlists inside one library stay as arrays
/// (§6.5): one library has one authority and no concurrent editors, and
/// generalising this where it is not needed would be cost without benefit.
enum SharedOrder {

    /// The alphabet, and the two ends of it.
    ///
    /// Digits and lower-case letters, in ASCII order, so a plain string
    /// comparison is the ordering -- no collation, no locale, nothing that
    /// could sort differently on another device or in another database. This is
    /// why the set excludes upper case: 'Z' < 'a' in ASCII, and a key that
    /// mixed them would order differently than it reads.
    static let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz")
    private static var first: Character { alphabet.first! }
    private static var last: Character { alphabet.last! }

    /// A key for an entry placed between `before` and `after`.
    ///
    /// Either end may be nil: nil `before` means "first in the list", nil
    /// `after` means "last". Both nil is the first entry in an empty setlist.
    ///
    /// The result is strictly greater than `before` and strictly less than
    /// `after`, by string comparison, always. That is the only property callers
    /// need and the only one the tests assert.
    static func between(_ before: String?, _ after: String?) -> String {
        let lower = before ?? ""
        // An empty `after` would mean "less than everything", which no key can
        // be; nil is spelled as "no upper bound" instead.
        guard let upper = after, !upper.isEmpty else {
            return appendMidpoint(after: lower)
        }
        if lower.isEmpty { return below(Array(upper), prefix: "") }
        return midpoint(lower, upper)
    }

    /// Keys for a whole list, evenly spread, for a setlist arriving at once.
    ///
    /// Used when a setlist is created or imported: n entries get n keys with
    /// room between each, so the first reorder does not have to lengthen a key.
    static func spread(count: Int) -> [String] {
        guard count > 0 else { return [] }
        var keys: [String] = []
        var previous: String? = nil
        for _ in 0..<count {
            let key = between(previous, nil)
            keys.append(key)
            previous = key
        }
        return keys
    }

    // MARK: - the three cases

    /// Past the end: step the last character up, or extend.
    private static func appendMidpoint(after lower: String) -> String {
        guard let tail = lower.last, let index = alphabet.firstIndex(of: tail) else {
            // an empty list: start in the MIDDLE of the alphabet, not at the
            // beginning, so the first insertion before it has room without
            // needing to lengthen
            return String(alphabet[alphabet.count / 2])
        }
        if index + 1 < alphabet.count {
            let step = (index + alphabet.count) / 2      // halfway to the top
            if step > index { return String(lower.dropLast()) + String(alphabet[step]) }
        }
        // the tail is already the largest character: keep it and extend, which
        // is strictly greater than `lower` because it is a prefix plus more
        return lower + String(alphabet[alphabet.count / 2])
    }

    /// A key strictly less than `upper`, extending `prefix`.
    ///
    /// THE RULE THIS ENFORCES, and the reason it is one function rather than
    /// two: **a key never ends in the minimum character.** A key ending in '0'
    /// has nothing beneath it at that length, so the next request to go below
    /// it returns the key itself and the order stops being editable. Both
    /// callers -- inserting at the head of the list, and squeezing under a key
    /// that is a prefix of another -- hit that wall, and each grew its own
    /// wrong answer before this was pulled out: prepending produced "0" and
    /// then "0h", which is greater than "0".
    ///
    /// A leading run of minimum characters cannot be halved, so it is consumed
    /// into the prefix and the decision moves one place right.
    private static func below(_ upper: [Character], prefix: String) -> String {
        var out = prefix
        var rest = upper
        while let c = rest.first, alphabet.firstIndex(of: c) == 0 {
            out.append(c)
            rest.removeFirst()
        }
        guard let c = rest.first, let index = alphabet.firstIndex(of: c) else {
            // `upper` is nothing but minimum characters. Our own keys never
            // are, so this is defensive: a shorter string of them is less.
            return out.isEmpty ? String(alphabet[alphabet.count / 2]) : String(out.dropLast())
        }
        let half = index / 2
        if half > 0 { return out + String(alphabet[half]) }
        // Halving lands on the minimum, which may not end a key: go one deeper.
        return out + String(first) + String(alphabet[alphabet.count / 2])
    }

    /// Strictly between two non-empty keys.
    private static func midpoint(_ lower: String, _ upper: String) -> String {
        var prefix = ""
        var lowerRest = Array(lower)
        var upperRest = Array(upper)
        // Walk the shared prefix. While the characters agree there is no room
        // between them, so the decision moves one place right.
        while let l = lowerRest.first, let u = upperRest.first, l == u {
            prefix.append(l)
            lowerRest.removeFirst()
            upperRest.removeFirst()
        }
        let li = lowerRest.first.flatMap { alphabet.firstIndex(of: $0) }
        let ui = upperRest.first.flatMap { alphabet.firstIndex(of: $0) }

        switch (li, ui) {
        case let (l?, u?) where u - l > 1:
            // room between the two characters
            return prefix + String(alphabet[(l + u) / 2])
        case let (l?, _?):
            // adjacent characters: take the lower one and go deeper, which
            // keeps the result below `upper` whatever follows
            return prefix + String(alphabet[l])
                + appendMidpoint(after: String(lowerRest.dropFirst()))
        case (nil, _):
            // `lower` ran out: it is a prefix of `upper`, so anything appended
            // is greater than it, and staying BELOW `upper` is the hard half.
            return below(upperRest, prefix: prefix)

        case let (l?, nil):
            // `upper` ran out, which the caller should not allow: an upper
            // bound that is a prefix of the lower bound is not an ordering.
            return prefix + String(alphabet[l]) + String(alphabet[alphabet.count / 2])
        case (nil, nil):
            return prefix + String(alphabet[alphabet.count / 2])
        }
    }
}
