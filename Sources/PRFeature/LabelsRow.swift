import SwiftUI
import TerminalUI

/// Labels as chips, with the repository's own behind a menu of
/// toggles; shared by the creation form and the open conversation.
struct LabelsRow: View {
    // MARK: Internal

    let picked: [String]
    let available: [String]
    let isEnabled: Bool
    let help: String
    let onToggle: (String) -> Void

    var body: some View {
        HStack(spacing: Self.spacing) {
            Text("Labels").font(.caption).foregroundStyle(.secondary)
            ForEach(picked, id: \.self) { label in
                Text(label)
                    .font(.caption)
                    .padding(.horizontal, Self.chipPadding)
                    .padding(.vertical, Self.chipVerticalPadding)
                    .background(.quaternary, in: Capsule())
            }
            Menu {
                ForEach(available, id: \.self) { label in
                    Toggle(label, isOn: Binding(get: { picked.contains(label) }, set: { _ in onToggle(label) }))
                }
            } label: {
                Image(systemName: "tag")
                    .accessibilityLabel("Pick labels")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(isEnabled == false)
            .hoverHelp(help)
            Spacer()
        }
    }

    // MARK: Private

    private static let spacing: CGFloat = 8
    private static let chipPadding: CGFloat = 6
    private static let chipVerticalPadding: CGFloat = 3
}
