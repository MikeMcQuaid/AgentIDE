import AgentIDEDomain
import Foundation
import PRFeature
import ReviewFeature
import SwiftUI
import TerminalUI

// MARK: Utility tab content

extension RootView {
    /// The agent terminal: copies are prose, so multi-line copies
    /// reflow for pasting into chat and pull request bodies.
    func agentTerminal(for session: AgentSession, at worktreePath: String, isActive: Bool) -> some View {
        // A pasted file or screenshot reaches the agent the way a
        // dropped one does. Bound first: as the call's last argument
        // the formatter would make it trailing, which fights SwiftLint.
        let pasteFiles: ([URL]) -> Bool = { urls in dropFiles(urls, into: session.name) }
        // The whole recent output from herdr: the local buffer holds
        // only the screen, so a selection can never reach what was
        // scrolled past.
        let readAll: () async -> String? = { await dependencies.service.readOutput(sessionName: session.name) }
        return TerminalPaneView(
            command: session.paneID.map(dependencies.service.attachCommand(paneID:)) ?? [],
            reflowsCopies: true,
            isActive: isActive,
            fixedAppearance: dependencies.service.launchAppearance(worktreePath: worktreePath),
            onPasteFiles: pasteFiles,
            onCopyAllOutput: readAll,
        )
        // A hair of room either side: the agent's own frames draw to
        // their last column, which sat against the pane's edges.
        .padding(.horizontal, Self.terminalInset)
    }

    /// The host shell terminal, a plain local shell on the pane's
    /// own PTY: no server to wedge and nothing left behind when the
    /// app quits. Copies stay verbatim for code. The pane stays
    /// mounted behind other tabs, worktrees and pages, so it reports
    /// whether it is the visible one and yields keyboard focus
    /// otherwise.
    func shellTerminal(
        at path: String,
        onExit: @escaping @MainActor () -> Void,
        isActive: Bool,
    ) -> TerminalPaneView {
        TerminalPaneView(
            shellIn: path,
            environment: dependencies.service.shellEnvironment(),
            isActive: isActive,
            onProcessTerminated: onExit,
        )
    }

    /// The one editor implementation, filling whichever slot asked:
    /// the utility pane's Editor tab or the centre pane. The file a
    /// command waits on goes only to the preferred slot, so it can
    /// never take over both, and the move button is offered only
    /// while the other slot could take the file.
    func editorPane(for item: WorktreeItem, role: EditorPane.Role) -> EditorPane {
        let path = item.worktree.path
        let prefersCentre = centreShowsEditor(for: item)
        let canMove = role == .centre || centreCanShowEditor(for: item)
        return EditorPane(
            worktreePath: path,
            service: dependencies.service,
            role: role,
            onMoveFile: canMove
                ? { file, line in receiveMoved(file: file, line: line, at: path, into: role.other) }
                : nil,
            // The closure stays a non-final argument: the formatter
            // rewrites a trailing one after a multiline call.
            onFinishedWaiting: { finishedWaitingEdit() },
            waitingEdit: (role == .centre) == prefersCentre ? waitingEdit(in: path) : nil,
        )
    }

    /// The worktree the review surfaces describe: on the repository
    /// page, the conversation selected in the list wins, so clicking
    /// around conversations retargets Review and PRs.
    func reviewTarget(for item: WorktreeItem, conversationPath: String?) -> WorktreeItem {
        guard item.worktree.path == item.worktree.repositoryPath,
              let path = conversationPath,
              let match = repositoryItems(for: item).first(where: { $0.worktree.path == path })
        else {
            return item
        }

        return match
    }

    /// The non-terminal utility tabs' content.
    func switchedUtility(for item: WorktreeItem, conversationPath: String?) -> some View {
        let target = reviewTarget(for: item, conversationPath: conversationPath)
        // Review, the editor and the pull requests stay mounted and
        // hide, rather than being rebuilt on every tab switch: each
        // costs a git or GitHub read to come back, and flipping
        // between them showed a loading state every time.
        let shown = utilityTab
        // Top-aligned, as each of these was before they shared a
        // stack: a pane with nothing in it belongs at the top of the
        // pane, not floating in the middle of it.
        return ZStack(alignment: .top) {
            ReviewView(
                worktree: target.worktree,
                git: dependencies.git,
                github: dependencies.github,
                service: dependencies.service,
            )
            .hidden(shown != .review)
            editorPane(for: item, role: .utility)
                .hidden(shown != .editor)
            PullRequestsView(
                repository: Repository(
                    name: target.worktree.repositoryName,
                    path: target.worktree.isHostDirectory
                        ? target.worktree.path
                        : target.worktree.repositoryPath,
                ),
                items: repositoryItems(for: item),
                github: dependencies.github,
                service: dependencies.service,
                store: dependencies.store,
                branch: target.worktree.branch,
                worktreePath: target.worktree.path,
                defaultBranch: defaultBranch(of: item),
                isMainCheckout: target.worktree.path == target.worktree.repositoryPath,
            )
            .hidden(shown != .pullRequests)
            if shown == .errors {
                ErrorsPane()
            }
        }
    }
}
