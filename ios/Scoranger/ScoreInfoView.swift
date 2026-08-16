import SwiftUI

/// Read-only metadata sheet for a score: overview, the latest version's
/// parts, the version history, and any attached sources. Everything shown
/// comes from the manifest's ScoreDoc — no engine calls.
struct ScoreInfoView: View {
    let score: ScoreDoc
    @Environment(\.dismiss) private var dismiss

    private var latestParts: [PartDoc] {
        score.versions.first { $0.id == score.latest }?.parts
            ?? score.versions.last?.parts
            ?? []
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Overview") {
                    LabeledContent("Name", value: score.name)
                    if let title = score.title, !title.isEmpty {
                        LabeledContent("Title", value: title)
                    }
                    if let composer = score.composer, !composer.isEmpty {
                        LabeledContent("Composer", value: composer)
                    }
                    LabeledContent("Slug") {
                        Text(score.slug).font(.system(.caption, design: .monospaced))
                    }
                    if let latest = score.latest {
                        LabeledContent("Latest") {
                            Text(latest).font(.system(.caption, design: .monospaced))
                        }
                    }
                }
                if !latestParts.isEmpty {
                    Section("Parts (latest version)") {
                        ForEach(latestParts, id: \.index) { part in
                            partRow(part)
                        }
                    }
                }
                Section("Versions") {
                    ForEach(score.versions.reversed()) { v in
                        versionRow(v)
                    }
                }
                if let sources = score.sources, !sources.isEmpty {
                    Section("Sources") {
                        ForEach(sources) { source in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(source.id)
                                        .font(.system(.caption, design: .monospaced))
                                    Text(source.name)
                                }
                                if let parts = source.parts, !parts.isEmpty {
                                    Text(parts.map(\.name).joined(separator: ", "))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(score.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func partRow(_ part: PartDoc) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(part.name)
                Spacer()
                if let instrument = part.instrument, instrument != part.name {
                    Text(instrument)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            let detail = partDetail(part)
            if !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func partDetail(_ part: PartDoc) -> String {
        var bits: [String] = []
        if let clefs = part.clefs, !clefs.isEmpty {
            bits.append(clefs.joined(separator: ", "))
        }
        if let range = part.range, range.count == 2 {
            bits.append("\(range[0])–\(range[1])")
        }
        if let measures = part.measures {
            bits.append("\(measures) measure\(measures == 1 ? "" : "s")")
        }
        if let notes = part.notes {
            bits.append("\(notes) note\(notes == 1 ? "" : "s")")
        }
        return bits.joined(separator: " · ")
    }

    private func versionRow(_ v: VersionDoc) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(v.id).font(.system(.caption, design: .monospaced))
                Text(v.op).font(.caption)
                Spacer()
                if v.id == score.latest {
                    Text("latest")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let time = v.time {
                Text(time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
