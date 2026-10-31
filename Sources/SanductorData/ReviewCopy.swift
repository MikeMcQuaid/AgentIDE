import SanductorDomain

/// Compact bot feedback through the same HTML and code protection as the renderer.
public enum ReviewCopy {
    /// Keeps actionable bot feedback and preserves human comments verbatim.
    public static func text(_ comment: ReviewThreadComment) -> String {
        guard ReviewBot.codeRabbit.matches(comment.author) else {
            return comment.asText
        }

        let prefix = comment.author + ": "
        let source = String(comment.asText.dropFirst(prefix.count))
        guard let parsed = try? MarkdownHTML(source, compactReview: true).markdown else {
            return comment.asText
        }

        return prefix + parsed
    }

    /// Includes the file and line above the compact conversation.
    public static func text(_ thread: ReviewThread) -> String {
        thread.path + (thread.line.map { ":" + String($0) } ?? "") + "\n"
            + thread.comments.lazy.map { text($0) }.joined(separator: "\n")
    }

    /// Groups compact conversations by file.
    public static func digest(of threads: [ReviewThread]) -> String {
        ReviewThread.digest(of: threads, commentText: text)
    }
}
