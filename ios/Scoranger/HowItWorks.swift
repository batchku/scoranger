import SwiftUI

// Settings -> How Scoranger works. The explanation, the diagram of the
// pipeline, and the open-source projects the app is built on.
//
// The diagram is drawn HERE, in SwiftUI, rather than shipped as a picture.
// README.md's is Mermaid, which nothing on iOS renders, and an exported PNG of
// it would be the wrong answer twice: it would not grow with Dynamic Type, and
// VoiceOver would have an image where the reader has a diagram. Boxes and
// arrows made of views scale with the type and read aloud in order.
//
// The words and the list are `Pipeline`, in ScoreModel, where a test bundle
// with no host app can hold them to what actually ships.

// MARK: - The section

struct HowItWorksSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Metric.s20) {
            Text("Scoranger has three parts: a way in for a score, an engine that "
                 + "changes it, and a page to read it on. This is what each of them "
                 + "does.")
                .typeRole(.body)
                .foregroundStyle(Theme.Ink.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            PipelineDiagram()

            ForEach(Pipeline.passages) { passage in
                VStack(alignment: .leading, spacing: Theme.Metric.s6) {
                    Text(passage.title)
                        .typeRole(.titleS)
                        .foregroundStyle(Theme.Ink.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(passage.body)
                        .typeRole(.body)
                        .foregroundStyle(Theme.Ink.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("how-passage-\(passage.id)")
            }

            CreditsBlock()
        }
        .padding(Theme.Metric.panelPadding)
        // `.contain` BEFORE the identifier, and it is not decoration. A bare
        // `accessibilityIdentifier` on a container is inherited by every
        // descendant that does not set its own, so this one name replaced the
        // diagram's, the credits' and every passage's -- the whole section
        // came back as twenty elements all called "how-it-works". Declaring
        // the container a container is what stops the name going down.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("how-it-works")
    }
}

// MARK: - The diagram

/// The pipeline as boxes and arrows, drawn natively.
///
/// One column, always. The panel it lives in is 380-460pt wide even on a big
/// iPad, so a side-by-side branch would be cramped before Dynamic Type touched
/// it; the chat agent is drawn INDENTED above the engine instead, joined by its
/// own arrow, so the shape still says "joins here" rather than "and then".
struct PipelineDiagram: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(Pipeline.stages.enumerated()), id: \.element.id) { index, stage in
                if let arrival = stage.arrival {
                    PipelineArrow(caption: arrival)
                }
                if let branch = stage.branch {
                    PipelineBranch(branch: branch)
                }
                PipelineBox(title: stage.title,
                            detail: stage.detail,
                            locale: stage.locale,
                            accent: false,
                            identifier: "pipeline-\(stage.id)",
                            spoken: spoken(stage, step: index + 1))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("How a score moves through Scoranger, "
                            + "\(Pipeline.stages.count) steps")
        .accessibilityIdentifier("pipeline-diagram")
    }

    /// What VoiceOver reads for one box. The arrow's caption is folded in
    /// rather than spoken as a stop of its own: a reader moving through the
    /// diagram wants five things, not nine.
    private func spoken(_ stage: Pipeline.Stage, step: Int) -> String {
        var parts = ["Step \(step) of \(Pipeline.stages.count). \(stage.title)."]
        if let arrival = stage.arrival { parts.append("Receives \(arrival).") }
        parts.append(stage.detail)
        if let locale = stage.locale.label { parts.append("Runs \(locale).") }
        return parts.joined(separator: " ")
    }
}

/// A box in the diagram.
private struct PipelineBox: View {
    let title: String
    let detail: String
    let locale: Pipeline.RunsOn
    /// The branch, which is not on the road the music travels.
    let accent: Bool
    let identifier: String
    let spoken: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Metric.s6) {
            // The title and its "where" wrap together: at an accessibility
            // type size a fixed row of the two puts the tag off the edge.
            Text(title)
                .typeRole(.titleS)
                .foregroundStyle(accent ? Theme.Accent.clayStrong : Theme.Ink.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let label = locale.label {
                PipelineTag(text: label, network: locale == .network)
            }
            Text(detail)
                .typeRole(.body)
                .foregroundStyle(Theme.Ink.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Metric.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent ? Theme.Accent.clayTint : Theme.Surface.well)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rInner, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier(identifier)
    }
}

/// "on this iPad" / "over the network", the one fact a musician without wifi
/// needs off a diagram. A type role rather than a fixed point size, so it
/// grows with everything around it.
private struct PipelineTag: View {
    let text: String
    let network: Bool

    var body: some View {
        Text(text)
            .typeRole(.label)
            .foregroundStyle(network ? Theme.Accent.clayStrong : Theme.Ink.ink2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.Metric.s8)
            .padding(.vertical, 3)
            .background(network ? Theme.Accent.clayTint : Theme.Surface.panel)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rCtl,
                                        style: .continuous))
    }
}

/// The arrow between two boxes, and what travels down it.
///
/// The app's one line is a 1pt dashed rule, so that is the shaft. The head is
/// drawn rather than set as a glyph, for the reason the chord diagrams and the
/// whistle circles are: the rasterisers' fallback font has no arrowhead and
/// engraves an empty box where one is asked for.
private struct PipelineArrow: View {
    let caption: String

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Metric.s8) {
            VStack(spacing: 0) {
                Theme.Rule(vertical: true).frame(height: Theme.Metric.s16)
                ArrowHead()
                    .fill(Theme.Line.line2)
                    .frame(width: 9, height: 6)
            }
            .frame(width: Theme.Metric.s24)
            Text(caption)
                .typeRole(.meta)
                .foregroundStyle(Theme.Ink.ink3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }
}

private struct ArrowHead: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// The chat agent: indented, tinted, and pointing INTO the box below it. It is
/// not a step the music passes through, and drawing it in the column as if it
/// were would be the one dishonest thing a simplified diagram could do here.
private struct PipelineBranch: View {
    let branch: Pipeline.Branch

    var body: some View {
        // The spine RUNS PAST the branch, in the same column the arrows are
        // drawn in. Photographed without it, the arrow above -- which carries
        // notation to the ENGINE -- appeared to end at the agent, and the
        // diagram said the scanned music is handed to a language model. It is
        // not. The line continuing past the box is what says so.
        HStack(alignment: .top, spacing: 0) {
            Theme.Rule(vertical: true)
                .frame(width: Theme.Metric.s24)
            VStack(alignment: .leading, spacing: 0) {
                PipelineBox(title: branch.title,
                            detail: branch.detail,
                            locale: branch.locale,
                            accent: true,
                            identifier: "pipeline-\(branch.id)",
                            spoken: "Joining here: \(branch.title). \(branch.detail) "
                                  + (branch.locale.label.map { "Runs \($0). " } ?? "")
                                  + "It hands the next step \(branch.hands).")
                PipelineArrow(caption: branch.hands)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Credits

/// Who wrote the parts of this that Scoranger did not.
///
/// Not only a courtesy: BSD-3-Clause, MIT, Apache-2.0, zlib, MPL-2.0, the SIL
/// Open Font License, LGPL-3.0 and AGPL-3.0 all require the notice to travel
/// with the thing, and a shipped app with no screen carrying them is in breach
/// of several of them at once.
struct CreditsBlock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Metric.s16) {
            VStack(alignment: .leading, spacing: Theme.Metric.s6) {
                Text("Built on")
                    .typeRole(.titleS)
                    .foregroundStyle(Theme.Ink.ink)
                Text("Scoranger is a small amount of original code standing on a lot of "
                     + "other people's work. These are the projects it ships or calls, "
                     + "and the licence each of them is offered under.")
                    .typeRole(.body)
                    .foregroundStyle(Theme.Ink.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            ForEach(Pipeline.creditGroups) { group in
                VStack(alignment: .leading, spacing: Theme.Metric.s8) {
                    Text(group.title)
                        .typeRole(.label)
                        .foregroundStyle(Theme.Ink.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note = group.note {
                        Text(note)
                            .typeRole(.meta)
                            .foregroundStyle(Theme.Ink.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(group.credits) { credit in
                        CreditRow(credit: credit)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("credits-\(group.id)")
            }

            Text("The full licence texts travel with the code in Scoranger's "
                 + "repository, beside each project they belong to.")
                .typeRole(.meta)
                .foregroundStyle(Theme.Ink.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("credits")
    }
}

/// One project: its name, the licence it is offered under, and what it does
/// here. Stacked, never a row of columns: a name and a licence set side by side
/// collide the moment the type grows.
private struct CreditRow: View {
    let credit: Pipeline.Credit

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(credit.name)
                .typeRole(.row)
                .foregroundStyle(Theme.Ink.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(credit.licence)
                .typeRole(.dataS)
                .foregroundStyle(Theme.Ink.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Text(credit.role)
                .typeRole(.meta)
                .foregroundStyle(Theme.Ink.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Theme.Metric.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Theme.Rule() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(credit.name), \(credit.licence). \(credit.role)")
    }
}
