import SwiftUI
import Textual

/// Textual lays out and highlights code using the app's font and token colours.
struct MarkdownCodeStyle: StructuredText.CodeBlockStyle {
    // MARK: Internal

    static let highlighterTheme = StructuredText.HighlighterTheme(
        foregroundColor: DynamicColor(Color(nsColor: .textColor)),
        backgroundColor: DynamicColor(Color(nsColor: .quaternaryLabelColor)),
        tokenProperties: [
            "keyword": AnyTextProperty(.foregroundColor(DynamicColor(HighlightedLine.colour(for: .keyword)))),
            "string": AnyTextProperty(.foregroundColor(DynamicColor(HighlightedLine.colour(for: .string)))),
            "comment": AnyTextProperty(.foregroundColor(DynamicColor(HighlightedLine.colour(for: .comment)))),
            "number": AnyTextProperty(.foregroundColor(DynamicColor(HighlightedLine.colour(for: .number)))),
        ],
    )

    func makeBody(configuration: Configuration) -> some View {
        Overflow {
            configuration.label
                .font(codeStyle.font)
                .fixedSize(horizontal: false, vertical: true)
                .padding(MarkdownText.spacing)
        }
        .background(Color(nsColor: .quaternaryLabelColor))
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        .textual
        .blockSpacing(.init(top: 0, bottom: MarkdownText.spacing))
    }

    // MARK: Private

    private static let cornerRadius: CGFloat = 6

    private var codeStyle: CodeStyle = .init()
}
