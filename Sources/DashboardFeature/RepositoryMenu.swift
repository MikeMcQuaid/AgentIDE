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
                Divider()
                Button("Add local directory…", systemImage: "laptopcomputer") { addDirectory() }
                    .hoverHelp(
                        "List a directory of your own here for a shell, an editor and a diff; "
                            + "no agent ever runs in it",
                    )
                Divider()
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

    /// Asks for the directory, then lists it under this
    /// repository. Nothing is copied or changed on disk.
    private func addDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "A directory of your own to list under " + group.repository.name
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        Task { await model.addHostDirectory(url.path, to: group.repository) }
    }
}
