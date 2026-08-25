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
