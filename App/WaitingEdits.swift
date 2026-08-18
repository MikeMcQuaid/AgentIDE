import AgentIDEData
import AgentIDEDomain
import DashboardFeature
import Foundation
import Observation
import TerminalUI

/// The files commands outside the app are waiting to have edited,
/// watched for and brought to the front. A shell running `git rebase
/// -i` is stopped until one of them is dealt with, so a request
/// takes over the window rather than waiting to be noticed.
@Observable
@MainActor
final class WaitingEdits {
    // MARK: Lifecycle

    deinit {
        // The watching task is owned by the window.
    }

    // MARK: Internal

    /// Every request still waiting, oldest first.
    private(set) var all: [ExternalEdit] = []

    /// The file a command is waiting on in a worktree, which its
    /// editor pane shows instead of the finder.
    func edit(in worktreePath: String) -> ExternalEdit? {
        all.first { $0.belongs(toWorktree: worktreePath) }
    }

    /// Watches the spool for as long as the window lives, bringing
    /// each new request to the front and telling its shim the app
    /// has the file. Whatever the pane was showing comes back once
    /// nothing is waiting, so a rebase returns to its own shell.
    func watch(service: SessionService, dashboard: DashboardModel) async {
        for await edits in service.pendingEdits() {
            all = edits
            if edits.isEmpty {
                restorePane()
            }
            guard let edit = edits.first, edit.id != shown else {
                continue
            }

            shown = edit.id
            takeOverPane(for: edit, dashboard: dashboard)
            await service.claimEdit(edit)
        }
    }

    // MARK: Private

    /// The request already brought to the front, so each one
    /// interrupts once, and the tab to go back to afterwards.
    private var shown: String?
    private var previousTab: String?

    private func takeOverPane(for edit: ExternalEdit, dashboard: DashboardModel) {
        let items = dashboard.groups.flatMap(\.items)
        if let item = items.first(where: { edit.belongs(toWorktree: $0.worktree.path) }) {
            dashboard.select(item)
        }
        let defaults = UserDefaults.standard
        previousTab = previousTab ?? defaults.string(forKey: UtilityTabTarget.key)
        defaults.set(true, forKey: UtilityTabTarget.visibilityKey)
        defaults.set(UtilityTabTarget.editor, forKey: UtilityTabTarget.key)
    }

    private func restorePane() {
        guard let previousTab else {
            return
        }

        self.previousTab = nil
        UserDefaults.standard.set(previousTab, forKey: UtilityTabTarget.key)
    }
}
