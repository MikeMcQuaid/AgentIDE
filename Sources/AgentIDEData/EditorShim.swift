import Foundation

/// The `agentide` editor shim: a script inside the app bundle that a
/// shell pane finds on its `PATH`, so `git rebase -i` and `git
/// commit` there edit their files in the app's own editor and wait
/// for them. Shipping it in the bundle means the script the shell
/// runs is always the one the running app was built with.
struct EditorShim {
    // MARK: Lifecycle

    /// Creates the shim for a workspace. `directory` is the bundled
    /// `bin` by default, and the repository's own copy under test,
    /// where there is no app bundle to look in.
    init(paths: WorkspacePaths, directory: String? = nil) {
        self.paths = paths
        self.directory = directory ?? (Bundle.main.resourcePath ?? ".") + "/bin"
    }

    // MARK: Internal

    /// Where the shim is, which is what `which agentide` answers in
    /// a shell pane.
    var path: String {
        directory + "/agentide"
    }

    /// What a host shell needs to reach it: the shim's directory on
    /// `PATH`, the editor variables naming it, the spool it should
    /// write to and a flag shell configuration can test for. A login
    /// shell runs its own files after this, so anything it sets for
    /// itself wins; `AGENTIDE` is there so it can decide to.
    var environment: [String: String] {
        let command = path + " --wait"
        return [
            "AGENTIDE": "1",
            "AGENTIDE_EDITS": paths.editsDirectory,
            "EDITOR": command,
            "VISUAL": command,
            "GIT_EDITOR": command,
            // A login shell rebuilds its own PATH from this, so the
            // standard directories are here for the moment before it
            // does, and for a shell whose files never get that far.
            "PATH": directory + ":" + Self.standardPath,
        ]
    }

    // MARK: Private

    /// What a shell starts with when nothing hands it a PATH.
    private static let standardPath = "/usr/bin:/bin:/usr/sbin:/sbin"

    private let paths: WorkspacePaths
    private let directory: String
}
