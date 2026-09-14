import UIKit
import os

/// A scripted drag of the score, for measuring frame times on a device
/// nobody is holding.
///
/// UI automation on a physical device needs a person to accept a prompt on
/// it. Under `-autoDrag` the app moves its own scroll view instead: once the
/// score is laid out it zooms to 2x where zooming is allowed, then for thirty
/// seconds sets the content offset every display frame along a triangle wave
/// across the scrollable range in both axes -- the offsets a finger would
/// produce, delivered at display rate. `FrameProbe` times the frames as it
/// would for a finger, because everything after the offset (layout, the page
/// stack's re-evaluation, rasterising, compositing) is the same work. What it
/// cannot measure is touch delivery itself, which is UIKit's and cheap.
///
/// Prints `AUTODRAG` lines and the probe's `FRAMES` summary to stdout, which
/// `devicectl device process launch --console` shows on the Mac.
final class AutoDrag: NSObject {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-autoDrag") }
    static let duration: CFTimeInterval = 30
    static let period: CFTimeInterval = 2.5

    private weak var scroll: UIScrollView?
    private weak var probe: FrameProbe?
    private var link: CADisplayLink?
    private var startedAt: CFTimeInterval = 0
    private var waitedSince: CFTimeInterval = 0
    private var origin: CGPoint = .zero

    init(scroll: UIScrollView, probe: FrameProbe?) {
        self.scroll = scroll
        self.probe = probe
        super.init()
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        let top = Float(UIScreen.main.maximumFramesPerSecond)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: top, preferred: top)
        link.add(to: .main, forMode: .common)
        self.link = link
        print("AUTODRAG armed; screen max \(UIScreen.main.maximumFramesPerSecond) fps")
    }

    deinit { link?.invalidate() }

    private func finish(_ why: String) {
        probe?.forced = false
        probe?.publish()
        print("AUTODRAG \(why); \(probe?.lastSummary ?? "no probe")")
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let scroll else { return finish("scroll view gone") }
        if startedAt == 0 {
            // Wait for something to scroll: the engraving arrives after the
            // canvas does. Four quiet seconds after it is there, so the first
            // rasters have landed, then go.
            let scrollable = scroll.contentSize.width > scroll.bounds.width * 1.1
                || scroll.contentSize.height > scroll.bounds.height * 1.1
                || scroll.maximumZoomScale > scroll.zoomScale * 1.5
            if waitedSince == 0 { waitedSince = link.timestamp }
            guard scrollable else {
                if link.timestamp - waitedSince > 180 { finish("nothing to scroll after 180s") }
                return
            }
            if link.timestamp - waitedSince < 4 { return }
            if scroll.maximumZoomScale > scroll.zoomScale * 1.5 {
                scroll.setZoomScale(min(2, scroll.maximumZoomScale), animated: false)
            }
            origin = scroll.contentOffset
            startedAt = link.timestamp
            probe?.forced = true
            print("AUTODRAG start; zoom \(scroll.zoomScale) content \(scroll.contentSize) bounds \(scroll.bounds.size)")
            return
        }
        let elapsed = link.timestamp - startedAt
        guard elapsed < Self.duration else { return finish("done after \(Int(Self.duration))s") }
        // A triangle wave from 0 to 1 and back, one period at a time.
        let phase = (elapsed / Self.period).truncatingRemainder(dividingBy: 1)
        let wave = phase < 0.5 ? phase * 2 : 2 - phase * 2
        // At most three viewports each way per half period: a fast flick,
        // not a teleport across a 24,000pt strip in a second.
        let maxX = min(max(scroll.contentSize.width - scroll.bounds.width, 0), scroll.bounds.width * 3)
        let maxY = min(max(scroll.contentSize.height - scroll.bounds.height, 0), scroll.bounds.height * 3)
        scroll.contentOffset = CGPoint(x: origin.x + maxX * wave, y: origin.y + maxY * wave)
    }
}
