import Foundation

/// Display-only masking; saved prompts and launched commands keep their original contents.
public enum TokenRedaction {
    // MARK: Public

    /// Masks recognised credentials for display without changing stored prompts.
    public static func preview(_ text: String) -> String {
        pattern?.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1***",
        ) ?? text
    }

    // MARK: Private

    private static let pattern = try? NSRegularExpression(
        pattern: #"\b(sntryu_|sntrys_|gh[pousr]_|github_pat_)[A-Za-z0-9_]{20,}\b"#,
    )
}
