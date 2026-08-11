import AgentIDEDomain
import SwiftUI

/// One syntax-highlighted source line, shared by the diff, markdown
/// code fences and search results.
public enum HighlightedLine {
    /// The line as a single `Text`, for concatenation with prefixes.
    /// Unknown languages come back plain.
    public static func text(line: String, language: SyntaxLanguage?) -> Text {
        CodeHighlighter.tokens(for: line, language: language)
            .map { token in Text(token.text).foregroundStyle(colour(for: token.kind)) }
            .reduce(Text(""), +)
    }

    /// The one token colour mapping every code surface shares.
    public static func colour(for kind: SyntaxToken.Kind) -> Color {
        switch kind {
        case .keyword:
            .purple

        case .string:
            .red

        case .comment:
            .green

        case .number:
            .blue

        case .plain:
            .primary
        }
    }
}
