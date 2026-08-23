import AgentIDEDomain
import SwiftUI
import TerminalUI

/// A repository header's context menu and the confirmation its
/// delete item opens; a modifier so the header stays one expression.
struct RepositoryMenu: ViewModifier {
    // MARK: Internal

    let group: RepositoryGroup
    let model: DashboardModel

    @Binding var pending: Repository?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button("Refresh") { Task { await model.refreshRepository(path: group.repository.path) } }
                    .hoverHelp("Ask GitHub about this repository's branches and merge queue now")
                Button("Delete repository", role: .destructive) { pending = group.repository }
                    .disabled(group.deletionBlocker != nil)
                    .hoverHelp(
                        group.deletionBlocker.map { "Cannot delete: " + $0 }
                            ?? "Delete the checkout from disk; conversations stay readable",
                    )
            }
            .confirmationDialog(
                "Delete the checkout of " + group.repository.name + "?",
                isPresented: isPresented,
                titleVisibility: .visible,
            ) {
                Button("Delete repository", role: .destructive) {
                    pending = nil
                    Task { await model.deleteRepository(group.repository) }
                }
                Button("Cancel", role: .cancel) { pending = nil }
            } message: {
                Text("The checkout at " + group.repository.path + " and its home directory symlink are removed. "
                    + "It has no worktrees, no running agent, nothing uncommitted and is level with origin.")
            }
    }

    // MARK: Private

    private var isPresented: Binding<Bool> {
        Binding(
            get: { pending?.path == group.repository.path },
            set: { shown in
                if shown == false, pending?.path == group.repository.path {
                    pending = nil
                }
            },
        )
    }
}
