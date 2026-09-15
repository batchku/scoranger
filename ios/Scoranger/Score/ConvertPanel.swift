import SwiftUI

/// The OMR offer, as a panel state (SC13).
///
/// This is the fourth shape the question has had, and the first one a reader
/// meets without being told where to look. It was a row that popped the
/// screen it was on (0.6.x), then a switch that stayed and reported its stage
/// (0.6.8), then that switch plus a chip on the top bar (build 194). All
/// three sat behind `…`, so a scan opened as a PDF and said nothing about
/// what it could become.
///
/// Here the question opens WITH the scan and states the cost before the
/// answer, not after. Either answer closes it, and More's own row opens the
/// same state again -- which is what makes "Read as is" a reading choice
/// rather than a decision.
///
/// While the transcription runs this state is the report: the stage, the bar
/// the upload gives it, and the line that says the reader is not being held.
struct ConvertPanel: View {
    @EnvironmentObject var state: AppState
    /// Both answers close the panel; the caller records the answer so the
    /// offer does not reopen on the next page turn.
    var onAnswered: () -> Void

    private var omr: OMRControl {
        MakeEditable.control(status: state.omrHere)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // No Done while the question is open: the two answers ARE the way
            // out, and a third one would leave the reader unsure which of them
            // closing counts as. Running, Done is back -- the work carries on
            // without the panel.
            PanelHeader(title: ConvertOffer.heading(state.omrHere))
                .environment(\.panelDone, state.omrHere == nil ? nil : closeFromRunning)
            if state.omrHere == nil { offer } else { running }
        }
        .padding(.bottom, Theme.Metric.s16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("convert-panel")
    }

    /// Done while it runs is the panel's own close, not an answer: the
    /// question has already been answered by starting the work.
    private var closeFromRunning: () -> Void { onAnswered }

    private var offer: some View {
        VStack(alignment: .leading, spacing: Theme.Metric.s12) {
            PanelNote(text: ConvertOffer.reason)
            HStack(spacing: Theme.Metric.s8) {
                PanelButton(title: ConvertOffer.convert, kind: .primary,
                            identifier: "convert-run") {
                    state.makeEditable()
                    onAnswered()
                }
                PanelButton(title: ConvertOffer.readAsIs,
                            identifier: "convert-read-as-is") { onAnswered() }
                Spacer(minLength: 0)
            }
            Theme.Rule()
            PanelNote(text: ConvertOffer.caution)
        }
        .padding(.horizontal, Theme.Metric.panelSide)
    }

    private var running: some View {
        VStack(alignment: .leading, spacing: Theme.Metric.s12) {
            HStack(spacing: Theme.Metric.s8) {
                if omr.showsSpinner {
                    ProgressView().controlSize(.small).tint(Theme.Accent.clay)
                }
                Text(omr.detail).typeRole(.row).foregroundStyle(Theme.Ink.ink)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("convert-progress")
            .accessibilityLabel("Converting, \(omr.detail)")
            if let fraction = omr.fraction {
                ProgressView(value: fraction)
                    .tint(Theme.Accent.clay)
                    .frame(maxWidth: .infinity)
            }
            PanelNote(text: ConvertOffer.keepReading)
        }
        .padding(.horizontal, Theme.Metric.panelSide)
    }
}
