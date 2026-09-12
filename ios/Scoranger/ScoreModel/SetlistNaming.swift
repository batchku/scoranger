import Foundation

/// The name of a set list made from a selection (0.8.0 build 194, Ali's
/// item 5): the pieces' own names while they read as a phrase, then a count
/// -- never a date or a number a person has to rename. A name already taken
/// gets a count after it rather than a collision.
enum SetlistNaming {
    static func name(for names: [String], taken: Set<String> = []) -> String {
        let clean = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let base: String
        switch clean.count {
        case 0:  base = "New set list"
        case 1:  base = clean[0]
        case 2:  base = "\(clean[0]) and \(clean[1])"
        case 3:  base = "\(clean[0]), \(clean[1]) and \(clean[2])"
        default: base = "\(clean[0]), \(clean[1]) and \(clean.count - 2) more"
        }
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }
}
