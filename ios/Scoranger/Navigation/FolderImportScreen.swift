import SwiftUI

/// What a folder import would create, read before it is run.
///
/// A library arriving from another app is dozens of pieces, and the grouping is
/// inferred from the folder structure. That inference can be wrong, and finding
/// out afterwards means unpicking someone's whole library — so the plan is a
/// screen, and nothing is written until it is approved.
struct FolderImportScreen: View {
    @EnvironmentObject var state: AppState
    var onBack: () -> Void

    var body: some View {
        Screen(title: "Import folder",
               backLabel: "My library",
               subtitle: state.folderImportPlan?.folder.lastPathComponent,
               onBack: onBack) {
            if let plan = state.folderImportPlan {
                VStack(alignment: .leading, spacing: 0) {
                    if let result = state.folderImportResult {
                        PanelNote(text: result)
                            .padding(Theme.Metric.panelPadding)
                    } else {
                        header(plan)
                    }
                    BandHeader("Pieces")
                    ForEach(plan.pieces) { piece in
                        let excluded = state.folderImportExcluded.contains(piece.piece)
                        ScreenRow(title: piece.piece,
                                  value: excluded ? "skipped"
                                                  : countLabel(piece.arrangements.count),
                                  leads: false,
                                  isSelected: !excluded,
                                  identifier: "folder-piece-\(piece.piece)") {
                            // tap a piece to leave it out: a library usually
                            // holds something that does not belong, and taking
                            // it out here is easier than unpicking it after
                            if excluded {
                                state.folderImportExcluded.remove(piece.piece)
                            } else {
                                state.folderImportExcluded.insert(piece.piece)
                            }
                        }
                        ForEach(excluded ? [] : piece.arrangements) { arrangement in
                            ScreenRow(title: arrangement.name,
                                      value: arrangement.kind == "pdf" ? "PDF" : "notation",
                                      leads: false,
                                      identifier: "folder-arrangement-\(arrangement.file)") {}
                                .padding(.leading, Theme.Metric.stepIndent)
                        }
                    }
                }
                .padding(.bottom, Theme.Metric.s32)
            }
        }
    }

    @ViewBuilder
    private func header(_ plan: FolderImportPlan) -> some View {
        VStack(alignment: .leading, spacing: Theme.Metric.s12) {
            Text(summary(plan)).typeRole(.titleS).foregroundStyle(Theme.Ink.ink)
            if plan.ignored > 0 {
                // said out loud: a migration that quietly drops files is worse
                // than one that refuses
                PanelNote(text: "\(plan.ignored) file\(plan.ignored == 1 ? "" : "s") "
                          + "in that folder are not scores and will be left alone.")
            }
            PanelButton(title: state.folderImportBusy ? "Importing…" : "Import",
                        kind: .primary) {
                Task { await state.commitFolderImport() }
            }
            .disabled(state.folderImportBusy)
            .accessibilityIdentifier("folder-import-commit")
        }
        .padding(Theme.Metric.panelPadding)
    }

    /// What will actually be written, once the deselected pieces are taken out.
    private func summary(_ plan: FolderImportPlan) -> String {
        let kept = plan.pieces.filter { !state.folderImportExcluded.contains($0.piece) }
        let arrangements = kept.reduce(0) { $0 + $1.arrangements.count }
        let p = kept.count == 1 ? "1 piece" : "\(kept.count) pieces"
        let a = arrangements == 1 ? "1 arrangement" : "\(arrangements) arrangements"
        return "\(p), \(a)"
    }

    private func countLabel(_ n: Int) -> String {
        n == 1 ? "1 arrangement" : "\(n) arrangements"
    }
}
