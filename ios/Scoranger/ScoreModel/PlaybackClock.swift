import Combine
import Foundation
import QuartzCore
import UIKit

/// The play head's own clock: the sequencer's beat, read once per DISPLAY
/// FRAME while the music plays, and observed by nothing but the two views
/// that draw the line and park the strip.
///
/// Ali on 0.8.0 build 194: the cursor and the follow-scroll advance in
/// chunks. They did: `PlaybackEngine.beat` is polled twenty times a second,
/// which is right for a bar readout and a lamp and wrong for a line that is
/// supposed to glide -- at 120 a quaver is 250ms, so the line moved five
/// times per quaver and the strip jumped with it. Publishing the beat at
/// display rate on the engine itself would re-evaluate every view watching
/// the engine (the tray, its knobs, the top bar) 120 times a second; this
/// object is the beat's fast lane, and the engine's `beat` stays the slow
/// one for everything that reads a number rather than draws a position.
@MainActor
final class PlaybackClock: ObservableObject {
    @Published private(set) var beat: Double = 0

    func set(_ beat: Double) {
        if beat != self.beat { self.beat = beat }
    }
}

/// A display link that asks for the screen's best rate and calls back once a
/// frame. Its own small class because `CADisplayLink` wants an Objective-C
/// target, which a Swift actor-isolated engine is not.
final class PlayheadTicker: NSObject {
    private var link: CADisplayLink?
    private var onFrame: (() -> Void)?

    func start(onFrame: @escaping () -> Void) {
        stop()
        self.onFrame = onFrame
        let link = CADisplayLink(target: self, selector: #selector(tick))
        let top = Float(UIScreen.main.maximumFramesPerSecond)
        // ProMotion gives a display link 60 unless it asks for more; the
        // line is the one thing on the page that moves every frame.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: top, preferred: top)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        onFrame = nil
    }

    var isRunning: Bool { link != nil }

    @objc private func tick() { onFrame?() }

    deinit { link?.invalidate() }
}
