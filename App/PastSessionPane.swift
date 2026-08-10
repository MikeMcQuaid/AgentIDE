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
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if isResuming {
                    ProgressView().controlSize(.small)
                }
                Button("Resume here") { resumeHere() }
                    .controlSize(.small)
                    .disabled(item.session != nil || isResuming)
                    .hoverHelp("Continue this conversation in this worktree; disabled while a session is live here")
                Button("Resume in new worktree") { resumeInNewWorktree() }
                    .controlSize(.small)
                    .disabled(isResuming)
                    .hoverHelp("Create a fresh worktree and branch and continue this conversation there")
                Button("New session") {
                    dependencies.dashboard.newSessionRepository = Repository(
                        name: item.worktree.repositoryName,
                        path: item.worktree.repositoryPath,
                    )
                    dependencies.dashboard.showsNewSession = true
                }
                .controlSize(.small)
                .hoverHelp("Start a fresh agent session in this repository instead of resuming")
            }
            // Hugs the pane's top edge: no top inset.
            .padding([.horizontal, .bottom], Self.spacing)
            Divider()
            TranscriptLogView(entries: dependencies.service.transcriptEntries(for: past))
        }
    }

    // MARK: Private

    private static let spacing: CGFloat = 4

    /// Instant feedback while the resume launches: the buttons
    /// disable and a spinner shows immediately.
    @State private var isResuming = false

    private var title: String {
        guard past.title.isEmpty else {
            return past.title
        }

        return Date(timeIntervalSince1970: TimeInterval(past.modifiedAt))
            .formatted(.dateTime.day().month().hour().minute())
    }

    private func resumeHere() {
        isResuming = true
        Task {
            _ = try? await dependencies.service.resumePast(past, worktree: item.worktree)
            await onResumedHere()
            isResuming = false
        }
    }

    private func resumeInNewWorktree() {
        isResuming = true
        Task {
            let repository = Repository(
                name: item.worktree.repositoryName,
                path: item.worktree.repositoryPath,
            )
            _ = try? await dependencies.service.resumeInNewWorktree(past, repository: repository)
            await dependencies.dashboard.refresh()
            isResuming = false
        }
    }
}
