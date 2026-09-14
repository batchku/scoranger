import SwiftDraw
import UIKit
import XCTest

/// The photographs behind the two rendering defects: a tempo mark and italic
/// text, drawn the way the app draws them.
///
/// It is a unit test rather than a UI test because what is being photographed
/// is not a screen -- it is the output of `SVGForSwiftDraw.prepare` through
/// SwiftDraw, which is exactly the pipeline `PageRasteriser` runs for every
/// page the app shows. Photographing it here needs no host app, no library and
/// no simulator boot, and it crops to the corner of the page where the marks
/// are, so a person can see the face and the size without a magnifier.
///
/// Export them with:
///   xcodebuild test -project Scoranger.xcodeproj -scheme Scoranger \
///     -destination "platform=iOS Simulator,id=<udid>" \
///     -only-testing:ScorangerTests/MarksOnThePage -resultBundlePath out.xcresult
///   xcrun xcresulttool export attachments --path out.xcresult --output-path shots
final class MarksOnThePage: XCTestCase {

    /// How much bigger than the engraved page the photograph is drawn, so the
    /// digits of a tempo mark are legible in it.
    private let magnification: CGFloat = 4

    /// The corner of the page the marks live in, in the page's own points:
    /// tempo mark, measure numbers, the dynamic, the fingering and the first
    /// direction are all inside it.
    private let corner = CGRect(x: 0, y: 20, width: 620, height: 190)

    private func marksPage() throws -> String {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: "marks", withExtension: "svg",
                                   subdirectory: "Fixtures") else {
            XCTFail("missing fixture marks.svg")
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func photograph(_ svg: String, _ name: String) throws {
        let drawing = try XCTUnwrap(SVG(data: Data(svg.utf8)),
                                    "the page would not parse")
        let whole = drawing.rasterize(scale: magnification)
        let cropped = CGRect(x: corner.minX * magnification,
                             y: corner.minY * magnification,
                             width: corner.width * magnification,
                             height: corner.height * magnification)
        let image: UIImage
        if let cg = whole.cgImage?.cropping(to: cropped) {
            image = UIImage(cgImage: cg)
        } else {
            image = whole
        }
        let shot = XCTAttachment(image: image)
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The page as the app prepares it: the tempo digits at their engraved
    /// size, the tempo mark bold, the directions and the measure numbers
    /// italic.
    func testPhotographTheMarksAsTheAppDrawsThem() throws {
        try photograph(SVGForSwiftDraw.prepare(try marksPage()),
                       "marks-as-the-app-draws-them")
    }

    /// The same corner, straight out of Verovio and through SwiftDraw with
    /// none of our rewriting: the reference for what the engraver intended.
    /// SwiftDraw takes only the FIRST tspan of a text element, so this is not
    /// a page the app could ship -- it is the ruler the other photograph is
    /// measured against.
    func testPhotographWhatVerovioEngraved() throws {
        try photograph(try marksPage(), "marks-as-verovio-engraved-them")
    }
}
