import SwiftUI
import TerminalUI

// MARK: - FinderResultRow

/// One finder result row; its own view and file so the pane stays
/// within the length limits.
struct FinderResultRow: View {
    // MARK: Internal

    let file: String
    let line: Int?
    let preview: String?

    var body: some View {
        HStack(spacing: Self.padding) {
            Image(systemName: line == nil ? "doc.text" : "text.magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(file + (line.map { ":" + String($0) } ?? ""))
                .font(codeStyle.font)
                .lineLimit(1)
            if let preview {
                Text(preview)
                    .font(codeStyle.font)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Self.padding)
        .padding(.vertical, Self.rowVerticalPadding)
    }

    // MARK: Private

    private static let padding: CGFloat = 6
    private static let rowVerticalPadding: CGFloat = 2

    private var codeStyle: CodeStyle = .init()
}

// MARK: - FinderResult

/// One row of the result list: a file, or a content match with the
/// matched line's text; beside the row views so the pane's type
/// body stays within the length limit.
struct FinderResult: Identifiable, Hashable {
    let file: String
    let line: Int?
    var preview: String?

    var id: String {
        file + ":" + String(line ?? 0)
    }
}
