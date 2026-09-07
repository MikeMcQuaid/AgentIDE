import SwiftUI
import TerminalUI

/// The footer's buttons around editing an open pull request's title
/// and body. Split from the footer for length.
extension PullRequestFooterView {
    /// Leaves the edit without saving; Escape does the same.
    var cancelEditButton: some View {
        Button("Cancel") { model.cancelEditing() }
            .agentGlassButtonStyle()
            .keyboardShortcut(.cancelAction)
            .hoverHelp("Leave the title and body as they are on GitHub")
    }

    /// Saves the edit: the surface's one primary action.
    var saveEditButton: some View {
        BusyButton(
            "Save",
            busy: "Saving",
            prominent: true,
            disabled: model.prTitle.trimmingCharacters(in: .whitespaces).isEmpty,
        ) {
            if await model.saveEdits() == false {
                utilityTab = UtilityTabTarget.errors
            }
        }
        .keyboardShortcut(.return, modifiers: .command)
        .hoverHelp("Save the title and body to the pull request", shortcut: "⌘↩")
    }
}
