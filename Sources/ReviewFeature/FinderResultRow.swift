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
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: Self.padding) {
            Image(systemName: line == nil ? "doc.text" : "text.magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(file + (line.map { ":" + String($0) } ?? ""))
                .font(CodeStyle.font)
                .lineLimit(1)
            if let preview {
                Text(preview)
                    .font(CodeStyle.font)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Self.padding)
        .padding(.vertical, Self.rowVerticalPadding)
        .background(isHighlighted ? Color.accentColor.opacity(Self.highlightOpacity) : .clear)
        .contentShape(Rectangle())
    }

    // MARK: Private

    private static let padding: CGFloat = 6
    private static let highlightOpacity = 0.25
    private static let rowVerticalPadding: CGFloat = 2
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

// MARK: - FinderResultsList

/// The finder's result rows in a bounded scroll, the highlight kept
/// on screen; its own view so the pane's type body stays within the
/// length limit.
struct FinderResultsList: View {
    // MARK: Internal

    let results: [FinderResult]
    let highlighted: Int
    let onPick: (FinderResult) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        FinderResultRow(
                            file: result.file,
                            line: result.line,
                            preview: result.preview,
                            isHighlighted: index == highlighted,
                        )
                        .onTapGesture { onPick(result) }
                        .accessibilityAddTraits(.isButton)
                        .id(index)
                    }
                }
            }
            // Arrowing past the visible rows scrolls the highlight
            // into view rather than moving it off screen.
            .onChange(of: highlighted) { proxy.scrollTo(highlighted) }
        }
        .frame(maxHeight: Self.resultsHeight)
        .hoverHelp("Arrows move the highlight; return or a click opens")
    }

    // MARK: Private

    private static let resultsHeight: CGFloat = 180
}
