import Foundation

/// Reads the MEI that Verovio produces alongside the SVG and derives a durable
/// address for every element it can.
///
/// This is the half of the join that supplies meaning. Verovio's MEI carries
/// `xml:id` values identical to the ids in the SVG, plus the numbering the SVG
/// omits: `<measure n="7">`, `<staff n="1">`, `<layer n="1">`. So the SVG says
/// where a thing is drawn, the MEI says what it is, and the id ties them.
enum MEISemanticsParser {

    enum ParseError: Error, LocalizedError {
        case malformed(String)
        var errorDescription: String? {
            if case .malformed(let why) = self { return "Malformed MEI: \(why)" }
            return nil
        }
    }

    /// session id -> durable address.
    static func parse(_ mei: String) throws -> [String: ScoreAddress] {
        let delegate = Delegate()
        let parser = XMLParser(data: Data(mei.utf8))
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() else {
            throw ParseError.malformed(parser.parserError?.localizedDescription ?? "unknown")
        }
        return delegate.addresses
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var addresses: [String: ScoreAddress] = [:]

        private var measure = 0
        /// Measures whose @n is missing or non-numeric still need a stable
        /// number, so fall back to counting them in document order.
        private var measureCount = 0
        private var staffStack: [Int] = []
        private var layerStack: [Int] = []
        /// (measure, staff, layer, kind) -> how many seen, for `ordinal`.
        private var counters: [String: Int] = [:]

        func parser(_ parser: XMLParser, didStartElement name: String,
                    namespaceURI: String?, qualifiedName: String?,
                    attributes attrs: [String: String]) {
            switch name {
            case "measure":
                measureCount += 1
                measure = Int(attrs["n"] ?? "") ?? measureCount
            case "staff":
                staffStack.append(Int(attrs["n"] ?? "") ?? (staffStack.last ?? 0) + 1)
            case "layer":
                layerStack.append(Int(attrs["n"] ?? "") ?? 1)
            default:
                break
            }

            guard let id = attrs["xml:id"], let kind = ScoreElementKind(meiTag: name) else {
                return
            }
            // Control events (harm, dynam, fermata, slur, tie) sit under
            // <measure> rather than inside a staff, and name their staff with
            // an attribute instead.
            let staff = staffStack.last ?? Int(attrs["staff"] ?? "") ?? 0
            let layer = layerStack.last ?? Int(attrs["layer"] ?? "") ?? 0
            let key = "\(measure)/\(staff)/\(layer)/\(kind.rawValue)"
            let ordinal = counters[key] ?? 0
            counters[key] = ordinal + 1
            addresses[id] = ScoreAddress(staff: staff, measure: measure,
                                         layer: layer, kind: kind, ordinal: ordinal)
        }

        func parser(_ parser: XMLParser, didEndElement name: String,
                    namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "staff": _ = staffStack.popLast()
            case "layer": _ = layerStack.popLast()
            default: break
            }
        }
    }
}
