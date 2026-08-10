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
}
