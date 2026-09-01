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
}
