import AgentIDEData
import SwiftUI
import TerminalUI

struct FeedbackPromptEditor: View {
    // MARK: Lifecycle

    init(kind: FeedbackPrompt) {
        self.kind = kind
        _text = AppStorage(wrappedValue: kind.defaultText, kind.key)
    }

    // MARK: Internal

    let kind: FeedbackPrompt

    var body: some View {
        TextEditor(text: $text)
            .interfaceFont(.body)
            .frame(minHeight: Self.height)
            .accessibilityLabel(kind.rawValue)
        Button("Reset prompt", systemImage: "arrow.counterclockwise") { text = kind.defaultText }
            .buttonStyle(.glass)
            .controlSize(.small)
            .disabled(text == kind.defaultText)
    }

    // MARK: Private

    private static let height: CGFloat = 160

    @AppStorage private var text: String
}
