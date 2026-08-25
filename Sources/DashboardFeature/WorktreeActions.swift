import AgentIDEData
import AgentIDEDomain
import AppKit
import SwiftUI
import TerminalUI

/// A worktree row's own menu: refreshing, copying, git, unread and
/// the two ways a worktree ends, grouped with separators and the
/// destructive one last.
struct WorktreeActions: View {
    let item: WorktreeItem
    let model: DashboardModel

    /// Runs the merge-safe cleanup, which offers the forced delete
    /// when it refuses; owned by the sidebar, which shows that
    /// confirmation. Deliberately not the last argument: a trailing
    /// closure after a multiline call fights the formatter.
    let onCleanUp: () async -> Void

    @Binding var pendingForceDelete: (path: String, refusal: SessionService.CleanupRefusal?)?

    /// The worktree whose branch a new one is being stacked on;
    /// the sidebar owns the prompt, since a menu cannot hold one.
    @Binding var pendingStack: WorktreeItem?

    var body: some View {
        Button("Refresh") { Task { await model.refreshRepository(path: item.worktree.repositoryPath) } }
            .hoverHelp("Ask GitHub about this repository's branches and merge queue now")
        Divider()
        Button("Copy branch name") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.worktree.branch, forType: .string)
        }
        .hoverHelp("Copy this worktree's branch name")
        Button("Copy path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.worktree.path, forType: .string)
        }
        .hoverHelp("Copy this worktree's full path")
        Divider()
        Button("Fetch") { Task { await model.fetch(item: item) } }
            .hoverHelp("git fetch all remotes of this repository")
        if item.worktree.path == item.worktree.repositoryPath {
            Button("Fetch and Reset") { Task { await model.fetchAndReset(item: item) } }
                .hoverHelp(
                    "git fetch origin, then hard-reset to origin's default branch; local changes are lost",
                )
        }
        Button("Stack a branch on this one…") { pendingStack = item }
            .hoverHelp("Cut a branch on top of this one in the same worktree, which is how a stack grows")
        Divider()
        Button("Mark as unread") { Task { await model.markUnread(item: item) } }
            .hoverHelp("Show the unread dot until this worktree is next viewed")
        // Cleanup is the merge-time tidy, offered by hand for merges
        // the poll has not noticed yet or made outside GitHub; on the
        // main checkout it only makes sense off the default branch.
        if item.worktree.path != item.worktree.repositoryPath || model.isOffDefaultBranch(item) {
            Button("Clean up after merge") { Task { await onCleanUp() } }
                .hoverHelp(
                    item.worktree.path == item.worktree.repositoryPath
                        ? "Return to the default branch and safely delete this merged branch; "
                        + "dirty checkouts are left alone"
                        : "Remove this worktree once its branch is merged and clean; "
                        + "anything that would lose work asks first",
                )
        }
        if item.worktree.path != item.worktree.repositoryPath {
            Divider()
            Button("Delete worktree", role: .destructive) { pendingForceDelete = (item.worktree.path, nil) }
                .hoverHelp("Force-deletes the worktree and branch after confirming what would be lost")
        }
    }
}
