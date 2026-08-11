import SwiftUI
import TerminalUI

/// A quiet icon-only button showing or hiding one of the window's
/// panes.
/// The action is a non-final property so call sites keep it labelled;
/// a trailing closure after the multiline call fights SwiftFormat.
struct PaneToggleButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    let help: String

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.plain)
        .hoverHelp(help)
    }
}
