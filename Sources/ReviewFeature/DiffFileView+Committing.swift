import SwiftUI
import TerminalUI

/// The per-file commit tick; split from the file view for
/// length.
extension DiffFileView {
    /// The tick that says whether this file joins the next commit,
    /// shown only where a commit can happen at all.
    @ViewBuilder var commitTick: some View {
        if model.showsUncommitted, model.isReadOnly == false {
            Toggle(
                "Commit this file",
                isOn: Binding(
                    get: { model.isCommitting(file.path) },
                    set: { model.setCommitting($0, path: file.path) },
                ),
            )
            .toggleStyle(.checkbox)
            .labelsHidden()
            .hoverHelp("Include this file in the next commit")
        }
    }
}
