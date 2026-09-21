import AppKit
import SwiftUI
import TerminalUI

struct LocalReviewPromptView: View {
    // MARK: Internal

    @Bindable var model: LocalReviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            Text("Prompt for the main agent").interfaceFont(.headline)
            Text("Edit this prompt, then copy and paste it into the main agent pane when you are ready.")
                .interfaceFont(.callout)
                .foregroundStyle(.secondary)
            TextEditor(text: $model.prompt)
                .interfaceFont(.body, monospaced: true)
                .focused($isFocused)
            HStack {
                Button("Close") { dismiss() }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Copy prompt") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.prompt, forType: .string)
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: Self.width, minHeight: Self.height)
        .onAppear { isFocused = true }
    }

    // MARK: Private

    private static let spacing: CGFloat = 8
    private static let width: CGFloat = 620
    private static let height: CGFloat = 440

    @Environment(\.dismiss)
    private var dismiss
    @FocusState private var isFocused: Bool
}
