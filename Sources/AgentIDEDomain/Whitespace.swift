/// Text cleanup applied when the editor saves.
public enum Whitespace {
    /// Removes spaces and tabs from the end of every line, keeping
    /// the final-newline state as it was.
    public static func strippingTrailingWhitespace(_ text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                var trimmed = line
                while trimmed.last == " " || trimmed.last == "\t" {
                    trimmed = trimmed.dropLast()
                }
                return String(trimmed)
            }
            .joined(separator: "\n")
    }
}
