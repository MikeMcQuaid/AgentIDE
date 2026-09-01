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

    /// The text as saving should write it: trailing whitespace
    /// stripped and one final newline guaranteed, unless the file's
    /// `.editorconfig` says otherwise. Silence keeps the app's own
    /// tidying, which is what code review wants.
    public static func cleanedForSaving(_ text: String, settings: EditorConfigSettings) -> String {
        var cleaned = text
        if settings.trimsTrailingWhitespace != .disabled {
            cleaned = strippingTrailingWhitespace(cleaned)
        }
        if settings.insertsFinalNewline != .disabled {
            cleaned = ensuringTrailingNewline(cleaned)
        }
        return cleaned
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
