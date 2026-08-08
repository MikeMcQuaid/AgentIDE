import AgentIDEData
import AgentIDEDomain
import SwiftUI

/// The session's last assistant message, with the session actions.
struct FinalMessageView: View {
    // MARK: Lifecycle

    /// Creates the message view.
    init(item: WorktreeItem, service: SessionService) {
        self.item = item
        self.service = service
    }

    // MARK: Internal

    /// The message text with commit, close, resume and ship actions.
    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            actions
            ScrollView {
                Text(message.isEmpty ? "No agent output yet." : message)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(Self.spacing)
            }
            if let status {
                Text(status).font(.callout).foregroundStyle(.secondary).padding(.horizontal, Self.spacing)
            }
        }
        .padding(.top, Self.spacing)
        .task(id: item.id) { await reload() }
    }

    // MARK: Private

    private static let spacing: CGFloat = 8

    @State private var message = ""
    @State private var status: String?

    private let item: WorktreeItem
    private let service: SessionService

    private var actions: some View {
        HStack {
            Button("Commit outstanding work") {
                run { try await service.commitOutstanding(worktreePath: item.worktree.path) }
            }
            .disabled(item.isDirty == false)
            Button("Close session") {
                run {
                    guard let session = item.session else {
                        return
                    }

                    try await service.closeSession(sessionName: session.name, worktreePath: item.worktree.path)
                }
            }
            .disabled(item.session == nil)
            Button("Resume session") {
                run { try await service.resumeWorktree(item.worktree) }
            }
            Button("Push and open PR") {
                run { status = try await service.pushAndCreatePullRequest(worktree: item.worktree) }
            }
            Spacer()
        }
        .padding(.horizontal, Self.spacing)
    }

    private func reload() {
        if let session = item.session {
            message = service.finalMessage(session: session, worktreePath: item.worktree.path) ?? ""
            service.markSeen(sessionName: session.name)
        } else {
            message = ""
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        Task {
            do {
                try await work()
                status = "Done."
            } catch {
                status = error.localizedDescription
            }
        }
    }
}
