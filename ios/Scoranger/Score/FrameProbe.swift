import UIKit
import os

/// Frame timing while the reader drags the score, measured on the device.
///
/// The performance loop of 0.8.0 build 195 (Ali: dragging is laggy and gets
/// worse over time) needs a number, not an impression. Under `-frameProbe`
/// a CADisplayLink runs beside the score's scroll view and, while the scroll
/// view is tracking, dragging or decelerating, records every frame interval
/// against the interval the display promised. What comes out: frames drawn,
/// frames DROPPED (an interval more than one and a half times the promised
/// one counts the frames it swallowed), the worst interval, the average rate
/// over the whole drag, and the rate of each of the last seconds -- so a
/// degradation over time shows as a falling tail rather than an average.
///
/// Published where a UI test on the device can read it: a one-point view
/// inside the scroll view, identifier `frame-probe`, whose accessibility
/// label is the summary as JSON. Also written to the log, category `frames`.
final class FrameProbe {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-frameProbe") }

    private weak var scroll: UIScrollView?
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var frames = 0
    private var dropped = 0
    private var worst: Double = 0
    private var active: Double = 0
    /// Frames and active seconds per wall-clock second, for the tail.
    private var perSecond: [(second: Int, frames: Int, seconds: Double)] = []
    private var lastPublish: CFTimeInterval = 0
    let element = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    /// Set by `AutoDrag` while it moves the content itself, since a scripted
    /// scroll is neither tracking nor decelerating.
    var forced = false
    /// The summary as last published, for whoever drives the probe.
    private(set) var lastSummary = "{}"

    init(scroll: UIScrollView) {
        self.scroll = scroll
        element.alpha = 0.02
        element.isAccessibilityElement = true
        element.accessibilityIdentifier = "frame-probe"
        element.accessibilityLabel = "{}"
        scroll.addSubview(element)
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        // Ask for the display's best; without a range a display link on a
        // ProMotion screen may be given 60.
        let top = Float(UIScreen.main.maximumFramesPerSecond)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: top, preferred: top)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    deinit { link?.invalidate() }

    @objc private func tick(_ link: CADisplayLink) {
        defer { lastTimestamp = link.timestamp }
        guard let scroll else { return }
        // Keep the probe element in the viewport, so it is always on screen
        // for the accessibility tree.
        element.frame.origin = CGPoint(x: scroll.contentOffset.x + 2, y: scroll.contentOffset.y + 2)
        let moving = forced || scroll.isTracking || scroll.isDragging || scroll.isDecelerating
        guard moving, lastTimestamp > 0 else { return }
        let interval = link.timestamp - lastTimestamp
        let promised = link.targetTimestamp - link.timestamp
        guard promised > 0, interval < 1 else { return }
        frames += 1
        active += interval
        worst = max(worst, interval)
        if interval > promised * 1.5 {
            dropped += max(Int((interval / promised).rounded()) - 1, 1)
        }
        let second = Int(link.timestamp)
        if let last = perSecond.last, last.second == second {
            perSecond[perSecond.count - 1].frames += 1
            perSecond[perSecond.count - 1].seconds += interval
        } else {
            perSecond.append((second, 1, interval))
        }
        if link.timestamp - lastPublish > 0.5 { publish(); lastPublish = link.timestamp }
    }

    func publish() {
        let tail = perSecond.suffix(8).map { $0.seconds > 0 ? Int((Double($0.frames) / $0.seconds).rounded()) : 0 }
        let fps = active > 0 ? Double(frames) / active : 0
        let summary: [String: Any] = [
            "maxFPS": UIScreen.main.maximumFramesPerSecond,
            "frames": frames, "dropped": dropped,
            "fps": (fps * 10).rounded() / 10,
            "worstMs": (worst * 10000).rounded() / 10,
            "activeSeconds": (active * 10).rounded() / 10,
            "tailFPS": Array(tail),
        ]
        if let data = try? JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            element.accessibilityLabel = text
            lastSummary = text
            Logger(subsystem: "com.irllabs.scoranger", category: "frames").notice("\(text, privacy: .public)")
            print("FRAMES \(text)")
        }
    }
}
