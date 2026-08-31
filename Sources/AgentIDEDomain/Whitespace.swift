/// Text cleanup applied when the editor saves.
public enum Whitespace {
    /// Removes spaces and tabs from the end of every line, keeping
    /// the final-newline state as it was.
    public static func strippingTrailingWhitespace(_ text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .lazy
            .map { line in
                var trimmed = line
                while trimmed.last == " " || trimmed.last == "\t" {
                    trimmed = trimmed.dropLast()
                }
                return String(trimmed)
            }
            .joined(separator: "\n")
    }

    /// Guarantees exactly one newline ends the text, the shape every
    /// POSIX tool expects: stray blank lines at the end are trimmed
    /// to it, a missing one is added, and an empty file stays empty
    /// rather than gaining a blank line.
    public static func ensuringTrailingNewline(_ text: String) -> String {
        guard text.isEmpty == false else {
            return text
        }

        var trimmed = Substring(text)
        while trimmed.hasSuffix("\n") {
            trimmed = trimmed.dropLast()
        }
        return trimmed + "\n"
    }
}
