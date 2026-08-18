import SwiftUI
import TerminalUI

/// The review pane's find bar. Return and the arrows walk the
/// matches, Escape closes it, and the count says how many there are.
struct ReviewFindBar: View {
    // MARK: Internal

    @Bindable var model: ReviewModel

    /// Raised whenever Cmd-F is pressed, so the field takes focus
    /// again even when the bar is already open.
    let focusRequest: Int
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: Self.spacing) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Find in the diff", text: $model.findQuery)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { model.moveFind(by: 1) }
                .onKeyPress(.downArrow) { model.moveFind(by: 1); return .handled }
                .onKeyPress(.upArrow) { model.moveFind(by: -1); return .handled }
            Text(model.findSummary)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Button("Previous match", systemImage: "chevron.up") { model.moveFind(by: -1) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(model.findTargets.isEmpty)
                .hoverHelp("The match before this one (up arrow)")
            Button("Next match", systemImage: "chevron.down") { model.moveFind(by: 1) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(model.findTargets.isEmpty)
                .hoverHelp("The match after this one (return or down arrow)")
            Button("Close find", systemImage: "xmark") { onClose() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .hoverHelp("Close the find bar and clear its highlights (Escape)")
        }
        .padding(.horizontal, Self.padding)
        .padding(.vertical, Self.verticalPadding)
        .onExitCommand { onClose() }
        .task(id: focusRequest) { focused = true }
    }

    // MARK: Private

    private static let spacing: CGFloat = 6
    private static let padding: CGFloat = 8
    private static let verticalPadding: CGFloat = 4

    @FocusState private var focused: Bool
}
