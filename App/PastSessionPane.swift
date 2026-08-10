import AgentIDEDomain
import SessionFeature
import SwiftUI
import TerminalUI

/// A past conversation: its transcript log under a strip offering to
/// resume it here or in a fresh worktree.
struct PastSessionPane: View {
    // MARK: Internal

    let past: TranscriptSession
    let item: WorktreeItem
    let onResumedHere: @MainActor () async -> Void
    let dependencies: AppDependencies

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Self.spacing) {
                Text(past.title.isEmpty ? past.id : past.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Resume here") { resumeHere() }
                    .controlSize(.small)
                    .disabled(item.session != nil)
                    .hoverHelp("Continue this conversation in this worktree; disabled while a session is live here")
                Button("Resume in new worktree") { resumeInNewWorktree() }
                    .controlSize(.small)
                    .hoverHelp("Create a fresh worktree and branch and continue this conversation there")
            }
            // Hugs the pane's top edge: no top inset.
            .padding([.horizontal, .bottom], Self.spacing)
            Divider()
            TranscriptLogView(entries: dependencies.service.transcriptEntries(for: past))
        }
    }

    // MARK: Private

    private static let spacing: CGFloat = 4

    private func resumeHere() {
        Task {
            _ = try? await dependencies.service.resumePast(past, worktree: item.worktree)
            await onResumedHere()
        }
    }

    private func resumeInNewWorktree() {
        Task {
            let repository = Repository(
                name: item.worktree.repositoryName,
                path: item.worktree.repositoryPath,
            )
            _ = try? await dependencies.service.resumeInNewWorktree(past, repository: repository)
            await dependencies.dashboard.refresh()
        }
    }
}
