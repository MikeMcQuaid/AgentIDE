import AgentIDEDomain
@testable import TerminalUI
import Testing

/// Proves the tree-sitter grammars and their highlight queries load
/// and classify real code; a silent fallback to the pure tokenizer
/// would pass weaker tests without noticing.
@MainActor
struct CodeHighlighterTests {
    @Test
    func `every tree-sitter grammar loads and classifies`() {
        for language in [SyntaxLanguage.swift, .ruby, .shell, .python, .json, .typescript] {
            let classified = CodeHighlighter.classifiedRanges(in: "# x\n// y\n1", language: language)
            #expect(classified != nil, "grammar for \(language) did not load")
        }
    }

    @Test
    func `python lines classify through the grammar`() {
        let tokens = CodeHighlighter.tokens(for: "def add(first):  # sum", language: .python)
        #expect(tokens.contains { $0.kind == .keyword && $0.text == "def" })
        #expect(tokens.contains { $0.kind == .comment && $0.text.contains("sum") })
    }

    @Test
    func `swift tokens colour keywords, strings and comments`() {
        let line = "let count = \"hi\" // total"
        let tokens = CodeHighlighter.tokens(for: line, language: .swift)
        #expect(tokens.map(\.text).joined() == line)
        #expect(tokens.contains { $0.kind == .keyword && $0.text == "let" })
        #expect(tokens.contains { $0.kind == .string && $0.text.contains("hi") })
        #expect(tokens.contains { $0.kind == .comment && $0.text.contains("total") })
    }

    @Test
    func `ruby and shell lines classify through the grammar`() {
        let ruby = CodeHighlighter.tokens(for: "def add(first) # sum", language: .ruby)
        #expect(ruby.map(\.text).joined() == "def add(first) # sum")
        #expect(ruby.contains { $0.kind == .keyword && $0.text == "def" })
        #expect(ruby.contains { $0.kind == .comment })

        let shell = CodeHighlighter.tokens(for: "if true; then echo ok; fi", language: .shell)
        #expect(shell.map(\.text).joined() == "if true; then echo ok; fi")
        #expect(shell.contains { $0.kind == .keyword && $0.text == "if" })
    }

    @Test
    func `unknown languages come back plain`() {
        let tokens = CodeHighlighter.tokens(for: "plain words", language: nil)
        #expect(tokens == [SyntaxToken(kind: .plain, text: "plain words")])
    }
}
