import Foundation

/// Which entry of a worktree's stack the panes are looking at,
/// remembered per worktree so moving between the review and pull
/// request tabs keeps the same branch in view.
public enum StackSelection {
    // MARK: Public

    /// The remembered entry, nil when none was chosen yet.
    public static func branch(for worktreePath: String) -> String? {
        UserDefaults.standard.string(forKey: key(worktreePath))
    }

    /// Remembers an entry; nil forgets it.
    public static func remember(_ branch: String?, for worktreePath: String) {
        if let branch {
            UserDefaults.standard.set(branch, forKey: key(worktreePath))
        } else {
            UserDefaults.standard.removeObject(forKey: key(worktreePath))
        }
    }

    // MARK: Private

    private static func key(_ worktreePath: String) -> String {
        "stackSelection#" + worktreePath
    }
}
