import SwiftUI
import TerminalUI

// MARK: - LabelsRow

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
            Text("Labels").interfaceFont(.caption).foregroundStyle(.secondary)
            LabelChips(picked: picked)
            menu
            Spacer()
        }
    }

    var menu: some View {
        Menu {
            ForEach(available, id: \.self) { label in
                Toggle(label, isOn: Binding(get: { picked.contains(label) }, set: { _ in onToggle(label) }))
            }
        } label: {
            Image(systemName: "tag")
                .accessibilityLabel("Pick labels")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.glass)
        .fixedSize()
        .disabled(isEnabled == false)
        .hoverHelp(help)
    }

    // MARK: Private

    private static let spacing: CGFloat = 8
}

// MARK: - LabelChips

/// Applied labels wrap without reserving space for an empty row.
struct LabelChips: View {
    // MARK: Internal

    let picked: [String]

    var body: some View {
        FlowLayout(spacing: Self.spacing) {
            ForEach(picked, id: \.self) { label in
                Text(label)
                    .interfaceFont(.caption)
                    .padding(.horizontal, Self.chipPadding)
                    .padding(.vertical, Self.chipVerticalPadding)
                    .background(.quaternary, in: Capsule())
            }
        }
    }

    // MARK: Private

    private static let spacing: CGFloat = 8
    private static let chipPadding: CGFloat = 6
    private static let chipVerticalPadding: CGFloat = 3
}
