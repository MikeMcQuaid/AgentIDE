import AgentIDEDomain

/// The numbering drawn beside each diff line, and a hunk's text as
/// the file holds it. Split from the view body for length.
extension DiffFileView {
    /// Joins each line with its old and new line numbers; deletions
    /// advance only the old side, additions only the new.
    func numbered(_ hunk: DiffHunk) -> [NumberedLine] {
        var old = hunk.oldStart
        var new = hunk.newStart
        return hunk.lines.map { line in
            let numbers: String
            switch line.kind {
            case .context:
                numbers = Self.pad(old) + " " + Self.pad(new)
                old += 1
                new += 1

            case .deletion:
                numbers = Self.pad(old) + " " + Self.pad(nil)
                old += 1

            case .addition:
                numbers = Self.pad(nil) + " " + Self.pad(new)
                new += 1
            }
            return NumberedLine(line: line, numbers: numbers)
        }
    }

    /// A hunk's lines as the file holds them: the displayed text
    /// stands a space in for a blank line so its change colour has
    /// something to paint, and copying that would put a space where
    /// the file has nothing at all.
    static func copyText(of hunk: DiffHunk) -> String {
        hunk.lines.map(\.content).joined(separator: "\n")
    }
}
