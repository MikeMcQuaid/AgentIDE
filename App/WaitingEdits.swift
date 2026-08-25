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
            // Only a waiting request holds a pane; the others are
            // acted on and dropped as they arrive.
            all = edits.filter(\.waitsForAnswer)
            if all.isEmpty {
                restorePreviousPane()
            }
            for edit in edits where edit.waitsForAnswer == false {
                act(on: edit, dashboard: dashboard)
                await service.discardEdit(edit)
            }
            guard let edit = all.first, edit.id != shown else {
                continue
            }

            shown = edit.id
            takeOverPane(for: edit, dashboard: dashboard)
            await service.claimEdit(edit)
        }
    }

    /// Puts back whatever the utility pane was showing before a
    /// waiting file took it over. Called when the editor's own
    /// buttons finish one, so the pane comes back immediately rather
    /// than when the spool next answers, and again when nothing is
    /// waiting, which covers a command that went away by itself.
    func restorePreviousPane() {
        guard let previousTab else {
            return
        }

        self.previousTab = nil
        UserDefaults.standard.set(previousTab, forKey: UtilityTabTarget.key)
    }

    // MARK: Private

    /// The request already brought to the front, so each one
    /// interrupts once, and the tab to go back to afterwards.
    private var shown: String?
    private var previousTab: String?

    /// A request nothing waits on: a directory selects its worktree
    /// or repository, a file selects the worktree holding it and
    /// shows it in the editor. Anything outside every worktree says
    /// so in the messages pane rather than silently doing nothing.
    private func act(on edit: ExternalEdit, dashboard: DashboardModel) {
        let items = dashboard.groups.flatMap(\.items)
        let holder = items.first { item in
            edit.path == item.worktree.path || edit.path.hasPrefix(item.worktree.path + "/")
        }
        guard let item = holder ?? items.first(where: { edit.belongs(toWorktree: $0.worktree.path) }) else {
            // A file belonging to no worktree still opens, in
            // whichever worktree is on screen: being handed a path
            // from anywhere is the point of a command.
            guard edit.kind == .open, FileManager.default.isReadableFile(atPath: edit.path),
                  let showing = dashboard.selection
            else {
                ErrorLog.shared.report("Not a worktree AgentIDE knows: " + edit.path)
                return
            }

            FileOpener.open(absolutePath: edit.path, line: nil, worktreePath: showing.worktree.path)
            return
        }

        dashboard.select(item)
        guard edit.kind == .open else {
            return
        }
        guard edit.path.hasPrefix(item.worktree.path + "/") else {
            FileOpener.open(absolutePath: edit.path, line: nil, worktreePath: item.worktree.path)
            return
        }

        FileOpener.open(
            relativePath: String(edit.path.dropFirst(item.worktree.path.count + 1)),
            line: nil,
            worktreePath: item.worktree.path,
        )
    }

    private func takeOverPane(for edit: ExternalEdit, dashboard: DashboardModel) {
        let items = dashboard.groups.flatMap(\.items)
        if let item = items.first(where: { edit.belongs(toWorktree: $0.worktree.path) }) {
            dashboard.select(item)
        }
        let defaults = UserDefaults.standard
        // A tab the user has never switched by hand is not in the
        // defaults at all, and without a name to go back to the pane
        // used to stay on the editor once the command was answered.
        previousTab = previousTab ?? defaults.string(forKey: UtilityTabTarget.key) ?? UtilityTab.review.rawValue
        defaults.set(true, forKey: UtilityTabTarget.visibilityKey)
        defaults.set(UtilityTabTarget.editor, forKey: UtilityTabTarget.key)
    }
}
