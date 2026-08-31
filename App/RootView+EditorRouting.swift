import AgentIDEDomain
import DashboardFeature
import Foundation
import ReviewFeature

// MARK: - Editor slot routing

/// Where editor requests land. One `EditorPane` implementation fills
/// two slots, the centre pane and the utility pane's Editor tab;
/// openers write untargeted keys and the window, which knows the
/// selection and what its centre pane shows, routes each request to
/// the slot that should take it.
extension RootView {
    /// Whether the item's centre pane could be an editor: nothing
    /// session-shaped holds it. A live session always says no, which
    /// is what keeps an editor from ever covering one.
    func centreCanShowEditor(for item: WorktreeItem) -> Bool {
        item.worktree.isHostDirectory
            || (item.isPlaceholder == false
                && resumingWorktree != item.worktree.path
                && dependencies.dashboard.isAwaitingSession(item) == false
                && item.session == nil
                && startingSession != item.worktree.path)
    }

    /// Whether the item's centre pane is an editor right now: a
    /// directory of your own always, a worktree or repository page
    /// when it chose the editor and no session outranks it.
    func centreShowsEditor(for item: WorktreeItem) -> Bool {
        item.worktree.isHostDirectory
            || (centreEditorPaths.contains(item.worktree.path) && centreCanShowEditor(for: item))
    }

    /// Whether the worktree at a path shows its centre editor, for
    /// the waiting-edit takeover, which must leave the utility pane
    /// alone when the centre slot will show the file.
    func prefersCentreEditor(at path: String) -> Bool {
        let items = dependencies.dashboard.groups.flatMap(\.items)
        guard let item = items.first(where: { $0.worktree.path == path }) else {
            return false
        }

        return centreShowsEditor(for: item)
    }

    /// Sets a worktree's centre pane to its editor or back to its
    /// conversations.
    func setCentreEditor(_ shows: Bool, at path: String) {
        if shows {
            centreEditorPaths.insert(path)
        } else {
            centreEditorPaths.remove(path)
        }
    }

    /// An opener wrote the shared open-file keys: copy them to the
    /// slot that should show the file and reveal it.
    func routeOpenFileRequest() {
        let defaults = UserDefaults.standard
        let file = defaults.string(forKey: "editorFilePath") ?? ""
        let worktree = defaults.string(forKey: "editorFileWorktree") ?? ""
        guard file.isEmpty == false, worktree.isEmpty == false else {
            return
        }

        let role = preferredEditorRole(file: file, worktreePath: worktree)
        // An off-screen centre slot still remembering this file
        // would reopen it beside the routed copy when it next
        // shows; the file lives in one slot only.
        let other = role.other
        if defaults.string(forKey: other.key("editorFilePath")) == file,
           defaults.string(forKey: other.key("editorFileWorktree")) == worktree
        {
            defaults.set("", forKey: other.key("editorFilePath"))
        }
        defaults.set(file, forKey: role.key("editorFilePath"))
        defaults.set(defaults.integer(forKey: "editorFileLine"), forKey: role.key("editorFileLine"))
        defaults.set(worktree, forKey: role.key("editorFileWorktree"))
        bump(role.key("editorFileRequest"))
        revealEditor(role)
    }

    /// A finder menu item asked for focus: point the preferred
    /// slot's finder at the asked-for mode and reveal it.
    func routeFinderFocusRequest() {
        // The launch clears the counter; only real requests route.
        guard finderFocusRequest > 0 else {
            return
        }

        let defaults = UserDefaults.standard
        let role = preferredEditorRole(file: nil, worktreePath: nil)
        defaults.set(defaults.bool(forKey: "finderSearchesContents"), forKey: role.key("finderSearchesContents"))
        bump(role.key("finderFocusRequest"))
        revealEditor(role)
    }

    /// Lands a file moved from one editor slot in the other,
    /// revealing it; moving to the centre opens the centre editor.
    func receiveMoved(file: String, line: Int?, at worktreePath: String, into role: EditorPane.Role) {
        let defaults = UserDefaults.standard
        defaults.set(file, forKey: role.key("editorFilePath"))
        defaults.set(line ?? 0, forKey: role.key("editorFileLine"))
        defaults.set(worktreePath, forKey: role.key("editorFileWorktree"))
        bump(role.key("editorFileRequest"))
        if role == .centre {
            setCentreEditor(true, at: worktreePath)
        } else {
            revealEditor(.utility)
        }
    }

    /// A session appeared in a worktree whose centre pane was the
    /// editor: the session wins the centre, so the slot closes and
    /// its open file moves to the side editor. Typing survives
    /// because an editor saves on its way off screen.
    func displaceCentreEditors(nowRunning: Set<String>) {
        let defaults = UserDefaults.standard
        let centre = EditorPane.Role.centre
        for path in nowRunning where centreEditorPaths.contains(path) {
            setCentreEditor(false, at: path)
            guard defaults.string(forKey: centre.key("editorFileWorktree")) == path,
                  let file = defaults.string(forKey: centre.key("editorFilePath")), file.isEmpty == false
            else {
                continue
            }

            defaults.set("", forKey: centre.key("editorFilePath"))
            receiveMoved(
                file: file,
                line: defaults.integer(forKey: centre.key("editorFileLine")),
                at: path,
                into: .utility,
            )
        }
    }

    // MARK: Private

    /// The slot a request lands in: the side editor unless the
    /// centre pane is an editor, which takes it, and always the slot
    /// already holding the requested file, so one file never opens
    /// twice. Roles are tried centre first, matching what is on
    /// screen.
    private func preferredEditorRole(file: String?, worktreePath: String?) -> EditorPane.Role {
        let defaults = UserDefaults.standard
        let centreVisible = dependencies.dashboard.selection.map { centreShowsEditor(for: $0) } ?? false
        if let file, file.isEmpty == false, let worktreePath {
            for role in EditorPane.Role.allCases
                where defaults.string(forKey: role.key("editorFilePath")) == file
                && defaults.string(forKey: role.key("editorFileWorktree")) == worktreePath
            {
                // A file held by a centre slot that is not on screen
                // must not route into the void.
                if role == .utility || centreVisible {
                    return role
                }
            }
        }
        return centreVisible ? .centre : .utility
    }

    /// Shows the slot a request routed to: the utility pane and its
    /// Editor tab for the side slot; the centre slot is only ever
    /// preferred while already on screen.
    private func revealEditor(_ role: EditorPane.Role) {
        guard role == .utility else {
            return
        }

        showsUtilityPane = true
        utilityTabName = UtilityTab.editor.rawValue
    }

    /// Increments a storage-bus counter the slot's pane observes.
    private func bump(_ key: String) {
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: key) + 1, forKey: key)
    }
}
