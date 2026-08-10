import AgentIDEDomain
import SwiftUI

/// One syntax-highlighted source line, shared by the diff, the code
/// fences in transcript logs and search results.
public struct HighlightedLine: View {
    // MARK: Lifecycle

    /// Creates a highlighted line.
    public init(line: String, language: SyntaxLanguage?) {
        self.line = line
        self.language = language
    }

    // MARK: Public

    /// The concatenated coloured runs.
    public var body: some View {
        Self.text(line: line, language: language)
    }

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

    // MARK: Private

    private let line: String
    private let language: SyntaxLanguage?
}
