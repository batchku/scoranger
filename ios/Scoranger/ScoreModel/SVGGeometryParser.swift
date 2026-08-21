import CoreGraphics
import Foundation

/// Extracts per-element geometry from one page of Verovio SVG.
///
/// Verovio's output is a narrow, regular subset, which is what makes parsing it
/// ourselves reasonable rather than reckless: nested `<g>` groups carrying a
/// class and an id, `<path d=…>` for stems, beams, slurs and staff lines, and
/// `<use xlink:href="#E050-…">` for every glyph, all referring to a handful of
/// shared definitions in `<defs>` (12 in the sample score).
///
/// A group's frame is the union of everything drawn inside it, so a `g.note`
/// ends up bounding its notehead, stem, dots and accidental together.
///
/// Bounds only. This deliberately does not retain drawable paths: the display
/// list for direct vector rendering is Phase B, and the parser is shaped so it
/// can grow that without a second pass over the document.
enum SVGGeometryParser {

    struct Page {
        var size: CGSize
        /// Every classed group, in document order.
        var groups: [Group]
    }

    struct Group {
        var id: String
        var svgClass: String
        var frame: CGRect
    }

    enum ParseError: Error, LocalizedError {
        case malformed(String)
        var errorDescription: String? {
            if case .malformed(let why) = self { return "Malformed SVG: \(why)" }
            return nil
        }
    }

    static func parse(_ svg: String) throws -> Page {
        let delegate = Delegate()
        let parser = XMLParser(data: Data(svg.utf8))
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() else {
            throw ParseError.malformed(parser.parserError?.localizedDescription ?? "unknown")
        }
        guard let size = delegate.pageSize else {
            throw ParseError.malformed("no viewBox on <svg>")
        }
        return Page(size: size, groups: delegate.finished)
    }

    // MARK: -

    private final class Delegate: NSObject, XMLParserDelegate {
        var pageSize: CGSize?
        var finished: [Group] = []

        /// Glyph id -> its bounds in glyph-local units, from <defs>.
        private var glyphBounds: [String: CGRect] = [:]
        private var inDefs = false
        /// The <defs> glyph currently being measured.
        private var defsGlyphID: String?
        private var defsGlyphRect: CGRect = .null

        private struct Frame {
            var id: String?
            var svgClass: String?
            var transform: CGAffineTransform
            var rect: CGRect = .null
        }
        private var stack: [Frame] = []

        /// Text is the other way Verovio draws meaning: chord symbols, dynamics
        /// and staff labels are <text>/<tspan>, not glyphs. Position and size
        /// are inherited down the tspan chain the same way the renderer's
        /// flattenTextElements has to handle -- x/y from the nearest ancestor
        /// that supplies them (often the <text> itself), font-size from the
        /// nearest non-zero one, since the outer element carries font-size="0px".
        private struct TextContext {
            var x: Double?
            var y: Double?
            var fontSize: Double?
            var anchor: String?
        }
        private var textStack: [TextContext] = []
        private var pendingText = ""

        private func pushTextContext(_ attrs: [String: String]) {
            textStack.append(TextContext(x: Double(attrs["x"] ?? ""),
                                         y: Double(attrs["y"] ?? ""),
                                         fontSize: Self.pixels(attrs["font-size"]),
                                         anchor: attrs["text-anchor"]))
        }

        /// Emit a box for the characters gathered so far, then forget them.
        private func flushText() {
            defer { pendingText = "" }
            let text = pendingText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            var x: Double?, y: Double?, size: Double?, anchor: String?
            for ctx in textStack.reversed() {
                if x == nil { x = ctx.x }
                if y == nil { y = ctx.y }
                if size == nil, let s = ctx.fontSize, s > 0 { size = s }
                if anchor == nil { anchor = ctx.anchor }
            }
            guard let x, let y, let size, size > 0 else { return }
            // 0.55em per character is a serviceable average for the engraving
            // faces Verovio uses; hit-testing wants a slight over-estimate.
            let width = Double(text.count) * size * 0.55
            var originX = x
            switch anchor {
            case "end":    originX -= width
            case "middle": originX -= width / 2
            default:       break
            }
            let box = CGRect(x: originX, y: y - size, width: width, height: size * 1.2)
            accumulate(box.applying(stack.last?.transform ?? .identity))
        }

        /// "405px" -> 405
        private static func pixels(_ value: String?) -> Double? {
            guard let value else { return nil }
            return Double(value.replacingOccurrences(of: "px", with: ""))
        }

        func parser(_ parser: XMLParser, didStartElement name: String,
                    namespaceURI: String?, qualifiedName: String?,
                    attributes attrs: [String: String]) {
            switch name {
            case "svg":
                pageSize = Self.viewBoxSize(attrs)

            case "defs":
                inDefs = true

            case "g" where inDefs:
                // a glyph definition: <g id="E050-xxxx"><path d="…"/></g>
                defsGlyphID = attrs["id"]
                defsGlyphRect = .null

            case "g":
                let parent = stack.last?.transform ?? .identity
                let local = SVGTransform.parse(attrs["transform"])
                stack.append(Frame(id: attrs["id"], svgClass: attrs["class"],
                                   transform: local.concatenating(parent)))

            case "path":
                guard let d = attrs["d"], var box = SVGPathBounds.bounds(of: d) else { return }
                if inDefs {
                    box = box.applying(SVGTransform.parse(attrs["transform"]))
                    defsGlyphRect = defsGlyphRect.isNull ? box : defsGlyphRect.union(box)
                } else {
                    let t = SVGTransform.parse(attrs["transform"])
                        .concatenating(stack.last?.transform ?? .identity)
                    accumulate(box.applying(t))
                }

            case "use":
                // glyphs: position from the transform (and/or x/y), extent from
                // the referenced definition
                let href = (attrs["xlink:href"] ?? attrs["href"] ?? "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                guard let glyph = glyphBounds[href] else { return }
                var t = SVGTransform.parse(attrs["transform"])
                if let x = Double(attrs["x"] ?? ""), let y = Double(attrs["y"] ?? "") {
                    t = t.concatenating(CGAffineTransform(translationX: x, y: y))
                }
                t = t.concatenating(stack.last?.transform ?? .identity)
                accumulate(glyph.applying(t))

            case "text":
                pendingText = ""
                pushTextContext(attrs)

            case "tspan":
                flushText()          // a nested run starts: bank what preceded it
                pushTextContext(attrs)

            case "rect":
                // Verovio draws some furniture (barlines, beams) as rects
                guard let x = Double(attrs["x"] ?? ""), let y = Double(attrs["y"] ?? ""),
                      let w = Double(attrs["width"] ?? ""), let h = Double(attrs["height"] ?? "")
                else { return }
                let t = SVGTransform.parse(attrs["transform"])
                    .concatenating(stack.last?.transform ?? .identity)
                accumulate(CGRect(x: x, y: y, width: w, height: h).applying(t))

            default:
                break
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String,
                    namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "defs":
                inDefs = false

            case "g" where inDefs:
                if let id = defsGlyphID, !defsGlyphRect.isNull {
                    glyphBounds[id] = defsGlyphRect
                }
                defsGlyphID = nil
                defsGlyphRect = .null

            case "text":
                flushText()
                _ = textStack.popLast()

            case "tspan":
                flushText()
                _ = textStack.popLast()

            case "g":
                guard let frame = stack.popLast() else { return }
                // hand the extent up so ancestors bound their children
                if !frame.rect.isNull { accumulate(frame.rect) }
                if let id = frame.id, let svgClass = frame.svgClass, !frame.rect.isNull {
                    finished.append(Group(id: id, svgClass: svgClass, frame: frame.rect))
                }

            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard !textStack.isEmpty else { return }
            pendingText += string
        }

        /// Grow the innermost open group by `rect`.
        private func accumulate(_ rect: CGRect) {
            guard !rect.isNull, rect.width.isFinite, rect.height.isFinite,
                  !stack.isEmpty else { return }
            let i = stack.count - 1
            stack[i].rect = stack[i].rect.isNull ? rect : stack[i].rect.union(rect)
        }

        private static func viewBoxSize(_ attrs: [String: String]) -> CGSize? {
            if let box = attrs["viewBox"] {
                let parts = box.split(whereSeparator: { $0 == " " || $0 == "," })
                    .compactMap { Double($0) }
                if parts.count == 4 { return CGSize(width: parts[2], height: parts[3]) }
            }
            if let w = Double(attrs["width"] ?? ""), let h = Double(attrs["height"] ?? "") {
                return CGSize(width: w, height: h)
            }
            return nil
        }


    }
}

/// Bounding box of an SVG path `d` string.
///
/// Every coordinate, control points included, is folded into the box. That is a
/// superset of the true bounds of a curve, which is the right trade for
/// hit-testing: a lasso may catch a note slightly early, never miss one.
enum SVGPathBounds {

    static func bounds(of d: String) -> CGRect? {
        var rect = CGRect.null
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var command: Character = "M"
        var numbers: [Double] = []
        var index = d.startIndex

        func note(_ point: CGPoint) {
            rect = rect.isNull ? CGRect(origin: point, size: .zero)
                               : rect.union(CGRect(origin: point, size: .zero))
        }

        /// Consume the arguments gathered for `command`.
        func flush() {
            guard !numbers.isEmpty || command == "Z" || command == "z" else { return }
            let relative = command.isLowercase
            let c = Character(command.uppercased())
            var i = 0
            func next() -> Double { defer { i += 1 }; return i < numbers.count ? numbers[i] : 0 }

            switch c {
            case "M", "L", "T":
                while i < numbers.count {
                    let x = next(), y = next()
                    current = relative ? CGPoint(x: current.x + x, y: current.y + y)
                                       : CGPoint(x: x, y: y)
                    if c == "M", i == 2 { subpathStart = current }
                    note(current)
                }
            case "H":
                while i < numbers.count {
                    let x = next()
                    current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                    note(current)
                }
            case "V":
                while i < numbers.count {
                    let y = next()
                    current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                    note(current)
                }
            case "C":
                while i + 5 < numbers.count {
                    let p = (0..<3).map { _ -> CGPoint in
                        let x = next(), y = next()
                        return relative ? CGPoint(x: current.x + x, y: current.y + y)
                                        : CGPoint(x: x, y: y)
                    }
                    p.forEach(note)
                    current = p[2]
                }
            case "S", "Q":
                while i + 3 < numbers.count {
                    let p = (0..<2).map { _ -> CGPoint in
                        let x = next(), y = next()
                        return relative ? CGPoint(x: current.x + x, y: current.y + y)
                                        : CGPoint(x: x, y: y)
                    }
                    p.forEach(note)
                    current = p[1]
                }
            case "A":
                // rx ry rot large sweep x y — the endpoint bounds the arc well
                // enough once the radii are allowed for.
                while i + 6 < numbers.count {
                    let rx = next(), ry = next()
                    _ = next(); _ = next(); _ = next()
                    let x = next(), y = next()
                    let end = relative ? CGPoint(x: current.x + x, y: current.y + y)
                                       : CGPoint(x: x, y: y)
                    note(end)
                    note(CGPoint(x: end.x + rx, y: end.y + ry))
                    note(CGPoint(x: end.x - rx, y: end.y - ry))
                    current = end
                }
            case "Z":
                current = subpathStart
                note(current)
            default:
                break
            }
            numbers.removeAll(keepingCapacity: true)
        }

        while index < d.endIndex {
            let ch = d[index]
            if ch.isLetter {
                flush()
                command = ch
                if ch == "Z" || ch == "z" { flush() }
                index = d.index(after: index)
            } else if ch == "-" || ch == "+" || ch == "." || ch.isNumber {
                // scan one number, honouring exponents and sign-as-separator
                var end = index
                if d[end] == "-" || d[end] == "+" { end = d.index(after: end) }
                while end < d.endIndex {
                    let c = d[end]
                    if c.isNumber || c == "." {
                        end = d.index(after: end)
                    } else if c == "e" || c == "E" {
                        end = d.index(after: end)
                        if end < d.endIndex, d[end] == "-" || d[end] == "+" {
                            end = d.index(after: end)
                        }
                    } else {
                        break
                    }
                }
                if let value = Double(d[index..<end]) { numbers.append(value) }
                index = end
            } else {
                index = d.index(after: index)
            }
        }
        flush()
        return rect.isNull ? nil : rect
    }
}

/// SVG `transform` attribute -> CGAffineTransform.
enum SVGTransform {
    /// translate / scale / matrix / rotate, applied left to right as SVG
    /// specifies. Verovio emits translate and scale; the rest are cheap
    /// insurance.
static func parse(_ value: String?) -> CGAffineTransform {
        guard let value, !value.isEmpty else { return .identity }
        var result = CGAffineTransform.identity
        let scanner = Scanner(string: value)
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: " ,\n\t")
        while !scanner.isAtEnd {
            guard let name = scanner.scanUpToString("(")?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  scanner.scanString("(") != nil,
                  let body = scanner.scanUpToString(")") else { break }
            _ = scanner.scanString(")")
            let n = body.split(whereSeparator: { $0 == " " || $0 == "," })
                .compactMap { Double($0) }
            let step: CGAffineTransform
            switch name {
            case "translate":
                step = CGAffineTransform(translationX: n.first ?? 0,
                                         y: n.count > 1 ? n[1] : 0)
            case "scale":
                let sx = n.first ?? 1
                step = CGAffineTransform(scaleX: sx, y: n.count > 1 ? n[1] : sx)
            case "rotate":
                step = CGAffineTransform(rotationAngle: (n.first ?? 0) * .pi / 180)
            case "matrix" where n.count == 6:
                step = CGAffineTransform(a: n[0], b: n[1], c: n[2],
                                         d: n[3], tx: n[4], ty: n[5])
            default:
                step = .identity
            }
            result = step.concatenating(result)
        }
        return result
    }
}
