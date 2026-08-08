import AgentIDEDomain
import SwiftUI

// MARK: - DiffFileView

/// One file's hunks with tappable, selectable changed lines.
struct DiffFileView: View {
    // MARK: Internal

    let file: DiffFile
    let model: ReviewModel
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Self.lineSpacing) {
            HStack {
                Text(file.path).font(.headline.monospaced())
                Spacer()
                Button("Edit file", action: onEdit)
            }
            ForEach(Array(file.hunks.enumerated()), id: \.offset) { hunkIndex, hunk in
                hunkView(hunkIndex: hunkIndex, hunk: hunk)
            }
        }
        .padding(.bottom, Self.filePadding)
    }

    // MARK: Private

    private static let lineSpacing: CGFloat = 2
    private static let filePadding: CGFloat = 8

    private func hunkView(hunkIndex: Int, hunk: DiffHunk) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("@@ -\(hunk.oldStart) +\(hunk.newStart) @@")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            ForEach(Array(hunk.lines.enumerated()), id: \.offset) { lineIndex, line in
                DiffLineView(
                    line: line,
                    isSelected: isSelected(hunkIndex: hunkIndex, lineIndex: lineIndex),
                ) {
                    model.toggle(
                        file: file,
                        selection: DiffSelection(hunkIndex: hunkIndex, lineIndex: lineIndex),
                    )
                }
            }
        }
    }

    private func isSelected(hunkIndex: Int, lineIndex: Int) -> Bool {
        model.selections[file.path]?
            .contains(DiffSelection(hunkIndex: hunkIndex, lineIndex: lineIndex)) ?? false
    }
}

// MARK: - DiffLineView

/// One diff line, coloured by kind and tappable when changeable.
struct DiffLineView: View {
    // MARK: Internal

    let line: DiffLine
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        let text = Text(prefix + line.content)
            .font(.callout.monospaced())
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle().fill(.blue).frame(width: Self.selectionBarWidth)
                }
            }
        // Only changed lines are tappable, so only they carry the
        // button gesture and accessibility trait.
        if line.kind == .context {
            text
        } else {
            text
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
                .accessibilityAddTraits(.isButton)
        }
    }

    // MARK: Private

    private static let selectionBarWidth: CGFloat = 3
    private static let selectedOpacity = 0.35
    private static let unselectedOpacity = 0.15

    private var prefix: String {
        switch line.kind {
        case .context:
            "  "

        case .addition:
            "+ "

        case .deletion:
            "- "
        }
    }

    private var opacity: Double {
        isSelected ? Self.selectedOpacity : Self.unselectedOpacity
    }

    private var background: Color {
        switch line.kind {
        case .context:
            .clear

        case .addition:
            .green.opacity(opacity)

        case .deletion:
            .red.opacity(opacity)
        }
    }
}
