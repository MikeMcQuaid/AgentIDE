import AgentIDEDomain
import Testing

/// Exercises the pure line tokenizer used by the review pane.
struct SyntaxHighlighterTests {
    @Test
    func `detects languages from paths`() {
        #expect(SyntaxLanguage.language(forPath: "Sources/App/Root.swift") == .swift)
        #expect(SyntaxLanguage.language(forPath: "lib/formula.rb") == .ruby)
        #expect(SyntaxLanguage.language(forPath: "script/bootstrap.sh") == .shell)
        #expect(SyntaxLanguage.language(forPath: "Brewfile") == .ruby)
        #expect(SyntaxLanguage.language(forPath: ".github/workflows/tests.yml") == .yaml)
        #expect(SyntaxLanguage.language(forPath: "config.yaml") == .yaml)
        #expect(SyntaxLanguage.language(forPath: "README.md") == .markdown)
        #expect(SyntaxLanguage.language(forPath: "binary.png") == nil)
    }

    @Test
    func `highlights swift keywords, strings, comments and numbers`() {
        let tokens = SyntaxHighlighter.highlight(
            line: "let count = \"hi\" + 42 // total",
            language: .swift,
        )
        #expect(tokens.map(\.text).joined() == "let count = \"hi\" + 42 // total")
        #expect(tokens.contains(SyntaxToken(kind: .keyword, text: "let")))
        #expect(tokens.contains(SyntaxToken(kind: .string, text: "\"hi\"")))
        #expect(tokens.contains(SyntaxToken(kind: .number, text: "42")))
        #expect(tokens.last == SyntaxToken(kind: .comment, text: "// total"))
    }

    @Test
    func `highlights ruby and shell with hash comments`() {
        let ruby = SyntaxHighlighter.highlight(line: "def add # sum", language: .ruby)
        #expect(ruby.first == SyntaxToken(kind: .keyword, text: "def"))
        #expect(ruby.last == SyntaxToken(kind: .comment, text: "# sum"))

        let shell = SyntaxHighlighter.highlight(line: "if true; then echo 'x'; fi", language: .shell)
        #expect(shell.contains(SyntaxToken(kind: .keyword, text: "if")))
        #expect(shell.contains(SyntaxToken(kind: .string, text: "'x'")))
        #expect(shell.contains(SyntaxToken(kind: .keyword, text: "fi")))
    }

    @Test
    func `markdown colours headings and inline code`() {
        let heading = SyntaxHighlighter.highlight(line: "## Title", language: .markdown)
        #expect(heading == [SyntaxToken(kind: .keyword, text: "## Title")])

        let inline = SyntaxHighlighter.highlight(line: "Use `git status` often", language: .markdown)
        #expect(inline.map(\.text).joined() == "Use `git status` often")
        #expect(inline.contains(SyntaxToken(kind: .string, text: "`git status`")))
        #expect(SyntaxLanguage.language(forPath: "README.md") == .markdown)
    }

    @Test
    func `keywords inside words and strings stay plain`() {
        let tokens = SyntaxHighlighter.highlight(line: "letter = \"if x\"", language: .swift)
        #expect(tokens.contains(SyntaxToken(kind: .keyword, text: "let")) == false)
        #expect(tokens.contains(SyntaxToken(kind: .keyword, text: "if")) == false)
        #expect(tokens.map(\.text).joined() == "letter = \"if x\"")
    }
}
