import AgentIDEDomain
import SwiftUI
import TerminalUI

/// A repository header's context menu and the confirmation its
/// delete item opens; a modifier so the header stays one expression.
struct RepositoryMenu: ViewModifier {
    // MARK: Internal

    let group: RepositoryGroup
    let model: DashboardModel

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button("Refresh") { Task { await model.refreshRepository(path: group.repository.path) } }
                    .hoverHelp("Ask GitHub about this repository's branches and merge queue now")
                Button("Delete repository", role: .destructive) { isConfirming = true }
                    .disabled(group.deletionBlocker != nil)
                    .hoverHelp(
                        group.deletionBlocker.map { "Cannot delete: " + $0 }
                            ?? "Delete the checkout from disk; conversations stay readable",
                    )
            }
            .confirmationDialog(
                "Delete the checkout of " + group.repository.name + "?",
                isPresented: $isConfirming,
                titleVisibility: .visible,
            ) {
                Button("Delete repository", role: .destructive) {
                    Task { await model.deleteRepository(group.repository) }
                }
                Button("Cancel", role: .cancel) {
                    // Dismissing is all cancelling does.
                }
            } message: {
                Text("The checkout at " + group.repository.path + " and its home directory symlink are removed. "
                    + "It has no worktrees, no running agent, nothing uncommitted and is level with origin.")
            }
    }

    // MARK: Private

    /// Whether this repository's delete is waiting on its
    /// confirmation; owned here because nothing outside the menu
    /// reads it.
    @State private var isConfirming = false
}
