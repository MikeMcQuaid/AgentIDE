import AgentIDEData
import AgentIDEDomain
import SwiftUI
import TerminalUI

/// The session's last assistant message, with the session actions.
public struct FinalMessageView: View {
    // MARK: Lifecycle

    /// Creates the message view; `hasOpenPullRequest` gates the ship
    /// action.
    public init(item: WorktreeItem, service: SessionService, hasOpenPullRequest: Bool) {
        self.item = item
        self.service = service
        self.hasOpenPullRequest = hasOpenPullRequest
    }

    // MARK: Public

    /// The message text with commit, close, resume and ship actions.
    public var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            actions
            ScrollView {
                Text(message.isEmpty ? "The agent's last reply appears here once it says something." : message)
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
    private let hasOpenPullRequest: Bool

    /// Push makes sense with unpushed commits or without a pull
    /// request yet; nil upstream means nothing was ever pushed.
    private var canShip: Bool {
        (item.aheadOfUpstream ?? 1) > 0 || hasOpenPullRequest == false
    }

    /// One contextual session action: a live session closes, a
    /// closed one resumes; the pair never applies at once.
    private var actions: some View {
        HStack {
            Button("Commit outstanding work") {
                run { try await service.commitOutstanding(worktreePath: item.worktree.path) }
            }
            .disabled(item.isDirty == false)
            .hoverHelp(
                item.isDirty
                    ? "Commit changes the agent left uncommitted"
                    : "Nothing uncommitted in this worktree",
            )
            sessionAction
            shipAction
            Spacer()
        }
        .padding(.horizontal, Self.spacing)
    }

    @ViewBuilder private var sessionAction: some View {
        if let session = item.session {
            Button("Close session") {
                run {
                    try await service.closeSession(sessionName: session.name, worktreePath: item.worktree.path)
                }
            }
            .hoverHelp("Kill the tmux session; the worktree and conversation survive for resuming")
        } else {
            Button("Resume session") {
                run { try await service.resumeWorktree(item.worktree) }
            }
            .hoverHelp("Relaunch this worktree's last conversation where it left off")
        }
    }

    private var shipAction: some View {
        Button("Push and open PR") {
            run { status = try await service.pushAndCreatePullRequest(worktree: item.worktree) }
        }
        .disabled(canShip == false)
        .hoverHelp(
            canShip
                ? "Push the branch and open a pull request; the repository's template fills the body"
                : "Everything is pushed and the branch already has an open pull request",
        )
    }

    private func reload() {
        if let session = item.session {
            message = service.finalMessage(session: session, worktreePath: item.worktree.path) ?? ""
            service.markSeen(worktreePath: item.worktree.path)
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
