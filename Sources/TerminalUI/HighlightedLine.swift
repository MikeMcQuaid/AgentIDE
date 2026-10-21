import AgentIDEDomain
import SwiftUI

/// Syntax colours shared by diffs and Markdown code blocks.
public enum HighlightedLine {
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
