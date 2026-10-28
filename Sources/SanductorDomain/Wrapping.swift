// MARK: - Wrapping

/// Turning hard-wrapped prose back into one line per point.
public enum Wrapping {
    // MARK: Public

    /// Joins the lines a commit message wrapped by hand back into
    /// whole bullets and paragraphs. Commit bodies are wrapped to a
    /// narrow column, which reads as broken lines wherever the text
    /// is reflowed for its width instead, a pull request body most
    /// of all. Blank lines, headings, quotes, tables, list starts and
    /// fenced code are left exactly as they are, so only the
    /// continuations of a line move.
    public static func unwrapped(_ text: String) -> String {
        var lines = [String]()
        var isFenced = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let current = String(line)
            if current.trimmingLeadingSpaces().hasPrefix("```") {
                isFenced.toggle()
                lines.append(current)
                continue
            }
            guard isFenced == false,
                  let previous = lines.last,
                  isContinuation(current),
                  previous.isEmpty == false,
                  starts(block: previous) == false || isListItem(previous)
            else {
                lines.append(current)
                continue
            }

            lines[lines.count - 1] = previous + " " + current.trimmingLeadingSpaces()
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Private

    /// How far a line can be indented and still be prose rather than
    /// the indented code block four spaces make it.
    private static let codeIndent = 4

    /// Whether a line continues the one above rather than starting
    /// something of its own.
    private static func isContinuation(_ line: String) -> Bool {
        let body = line.trimmingLeadingSpaces()
        return body.isEmpty == false
            && line.prefix { $0 == " " }.count < codeIndent
            && line.hasPrefix("\t") == false
            && starts(block: line) == false
    }

    /// Whether a line opens a block of its own, which never joins
    /// the line above it.
    private static func starts(block line: String) -> Bool {
        let body = line.trimmingLeadingSpaces()
        return isListItem(line)
            || body.hasPrefix("#")
            || body.hasPrefix(">")
            || body.hasPrefix("|")
            || body.hasPrefix("---")
    }

    private static func isListItem(_ line: String) -> Bool {
        let body = line.trimmingLeadingSpaces()
        for marker in ["- ", "* ", "+ "] where body.hasPrefix(marker) {
            return true
        }
        // An ordered item: digits, then a dot or bracket, then a space.
        let digits = body.prefix(while: \.isNumber)
        let after = body.dropFirst(digits.count)
        return digits.isEmpty == false && (after.hasPrefix(". ") || after.hasPrefix(") "))
    }
}

private extension String {
    /// The line without its leading spaces and tabs.
    func trimmingLeadingSpaces() -> String {
        String(drop { $0 == " " || $0 == "\t" })
    }
}
