import AgentIDEDomain
import AppKit
import SwiftUI
import TerminalUI

/// A directory of your own has none of the worktree lifecycle: no
/// branch to delete, no session to clean up after, and forgetting it
/// stops it being listed while touching no file.
struct HostDirectoryActions: View {
    let item: WorktreeItem
    let model: DashboardModel

    var body: some View {
        Button("Fetch") { Task { await model.fetchHostDirectory(item) } }
            .hoverHelp("git fetch all remotes of this directory")
        Button("Checkout and pull default branch") {
            Task { await model.checkoutAndPullDefault(item) }
        }
        .hoverHelp("Switch to the default branch and fast-forward it; a diverged branch stops instead")
        Divider()
        Button("Copy path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.worktree.path, forType: .string)
        }
        .hoverHelp("Copy this directory's full path")
        Divider()
        Button("Forget this directory", role: .destructive) {
            Task { await model.forgetHostDirectory(item) }
        }
        .hoverHelp("Stop listing it here; nothing on disk is touched")
    }
}
