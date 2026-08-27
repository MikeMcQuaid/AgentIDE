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
}
