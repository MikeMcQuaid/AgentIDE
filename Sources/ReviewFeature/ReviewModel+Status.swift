import AgentIDEDomain
import TerminalUI

/// What the review pane says about its own work, in the footer and
/// in the messages pane, always naming the repository it is about.
/// Split from the model for length.
extension ReviewModel {
    /// Reports a failure into the app-wide error log; the local
    /// status line keeps success reports only.
    func report(_ message: String) {
        ErrorLog.shared.report(message, about: repositoryName)
    }

    /// The conversations anchored to one file.
    func threads(for path: String) -> [ReviewThread] {
        threads.filter { $0.path == path }
    }

    /// Whether a path looks generated.
    func isGenerated(_ path: String) -> Bool {
        Self.generatedFragments.contains { path.contains($0) }
    }

    /// Path fragments treated as generated and hidden by default.
    static let generatedFragments = [
        ".pbxproj", "Package.resolved", ".lock", "Gemfile.lock", ".xcassets",
    ]

    /// What a reload's reads came to. A failure is held for the next
    /// reload, which is the recovery a read has, unless the worktree
    /// itself has gone: one can vanish between the poll that mounted
    /// this pane and the reload that reads it (a branch renamed away,
    /// cleanup after a merge), which is the workspace changing, not
    /// a failure, and the sidebar drops the row on its own.
    func recordReload(_ error: (any Error)?) {
        let what = "Review of " + repositoryName
        guard let error else {
            ServiceStatus.shared.recordSuccess(doing: what)
            return
        }

        if worktreeExists(worktreePath) {
            ServiceStatus.shared.record(failure: error, doing: what)
        }
    }
}
