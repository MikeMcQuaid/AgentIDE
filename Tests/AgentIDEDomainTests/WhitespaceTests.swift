import AgentIDEDomain
import Testing

/// Exercises the editor's save-time cleanup.
struct WhitespaceTests {
    @Test
    func `strips trailing spaces and tabs but keeps structure`() {
        let input = "let a = 1  \nplain\n\tindented\t\n\nend"
        #expect(Whitespace.strippingTrailingWhitespace(input) == "let a = 1\nplain\n\tindented\n\nend")
    }

    @Test
    func `keeps a trailing newline when one exists`() {
        #expect(Whitespace.strippingTrailingWhitespace("line \n") == "line\n")
        #expect(Whitespace.strippingTrailingWhitespace("line") == "line")
    }

    @Test
    func `the save cleanup does what the configuration allows`() {
        let messy = "line  \n\n"
        // Silence keeps the app's own tidying.
        #expect(Whitespace.cleanedForSaving(messy, settings: EditorConfigSettings()) == "line\n")

        var refusing = EditorConfigSettings()
        refusing.trimsTrailingWhitespace = .disabled
        refusing.insertsFinalNewline = .disabled
        #expect(Whitespace.cleanedForSaving(messy, settings: refusing) == messy)
        #expect(Whitespace.cleanedForSaving("no newline", settings: refusing) == "no newline")

        var trimmingOnly = EditorConfigSettings()
        trimmingOnly.insertsFinalNewline = .disabled
        #expect(Whitespace.cleanedForSaving(messy, settings: trimmingOnly) == "line\n\n")
    }

    @Test
    func `saving guarantees exactly one final newline, except in an empty file`() {
        #expect(Whitespace.ensuringTrailingNewline("line") == "line\n")
        #expect(Whitespace.ensuringTrailingNewline("line\n") == "line\n")
        // Exactly one: stray blank lines at the end are trimmed too,
        // and a file of nothing but newlines keeps one.
        #expect(Whitespace.ensuringTrailingNewline("line\n\n") == "line\n")
        #expect(Whitespace.ensuringTrailingNewline("a\n\nb\n\n\n") == "a\n\nb\n")
        #expect(Whitespace.ensuringTrailingNewline("\n") == "\n")
        #expect(Whitespace.ensuringTrailingNewline("").isEmpty)
    }
}
