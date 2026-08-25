import Foundation
import SwiftUI

/// A live readout of what the canvas is actually receiving.
///
/// This exists because three hardware-only failures in a row could not be seen
/// from here: the simulator has no Pencil, no palm, and synthesizes its events
/// on a different path through the run loop. Each round cost a build and a user
/// who could only report "it doesn't work". With this switched on, the person
/// holding the iPad can read back exactly what the app saw — touch type, how
/// many are down, how long they were held, and whether the lasso began — which
/// turns an untestable bug into an observable one.
///
/// Off by default, behind a Settings toggle. It is a diagnostic, not a feature.
@MainActor
final class TouchDiagnostics: ObservableObject {
    static let shared = TouchDiagnostics()

    /// Most recent first, oldest dropped.
    @Published private(set) var lines: [String] = []
    /// The one-line summary of what is on the glass right now.
    @Published private(set) var current: String = "waiting for a touch"

    private static let keep = 12

    var isOn: Bool {
        UserDefaults.standard.bool(forKey: "touchDiagnostics")
    }

    /// One event, phrased the way the reader needs to read it back to us.
    func record(_ event: String) {
        guard isOn else { return }
        lines.insert(event, at: 0)
        if lines.count > Self.keep { lines.removeLast(lines.count - Self.keep) }
    }

    func setCurrent(_ summary: String) {
        guard isOn else { return }
        current = summary
    }

    func clear() {
        lines = []
        current = "waiting for a touch"
    }

    /// How a touch is described in the readout. Static and pure so the wording
    /// can be tested without a device.
    nonisolated static func describe(kind: String, phase: String, fingers: Int,
                                     pencilDown: Bool, heldFor: TimeInterval,
                                     markupActive: Bool, began: Bool,
                                     radius: CGFloat? = nil,
                                     distanceFromPencil: CGFloat? = nil) -> String {
        let held = String(format: "%.2fs", heldFor)
        let touching = pencilDown ? "pencil+\(fingers)f" : "\(fingers)f"
        var line = "\(kind) \(phase) · \(touching) · held \(held) · "
            + "markup \(markupActive ? "on" : "off") · "
            + (began ? "LASSO STARTED" : "no lasso")
        // The two numbers 0.3.0's finger-add rule will be tuned on. Printed for
        // every finger so the thresholds come from a real hand rather than a
        // guess: a fingertip should read small and far, a resting palm broad
        // and near.
        if let radius {
            line += String(format: " · r %.1f", radius)
            if let distanceFromPencil {
                line += String(format: " d %.0f", distanceFromPencil)
                line += LassoGate.isDeliberateModifierFinger(
                    radius: radius, distanceFromPencil: distanceFromPencil)
                    ? " → MODIFIER" : " → palm"
            }
        }
        return line
    }
}

/// The readout itself, over the canvas.
struct TouchDiagnosticsOverlay: View {
    @ObservedObject var diagnostics: TouchDiagnostics
    /// Read from the same default the recognizer checks, so the overlay and the
    /// recording switch on together.
    @AppStorage("touchDiagnostics") private var isOn = false

    var body: some View {
        if isOn {
            VStack(alignment: .leading, spacing: 2) {
                Text(diagnostics.current)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.Accent.clayStrong)
                ForEach(Array(diagnostics.lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.Ink.ink2)
                }
            }
            .padding(Theme.Metric.s8)
            .frame(maxWidth: 420, alignment: .leading)
            .background(Theme.Surface.panel.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rCtl))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                    .stroke(Theme.Line.line2, lineWidth: 1)
            }
            .padding(Theme.Metric.s12)
            .allowsHitTesting(false)
            .accessibilityIdentifier("touch-diagnostics")
        }
    }
}
