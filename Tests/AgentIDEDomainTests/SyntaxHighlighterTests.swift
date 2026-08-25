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
        // A picture gets nothing; anything else that is text gets
        // the generic treatment rather than reading as dead.
        #expect(SyntaxLanguage.language(forPath: "binary.png") == nil)
        #expect(SyntaxLanguage.language(forPath: "schema.sql") == .generic)
        #expect(SyntaxLanguage.language(forPath: "main.go") == .golang)
        #expect(SyntaxLanguage.language(forPath: "app/main.c") == .cSource)
        #expect(SyntaxLanguage.language(forPath: ".gitconfig") == .config)
        #expect(SyntaxLanguage.language(forPath: "~/.zshrc") == .shell)
        #expect(SyntaxLanguage.language(forPath: "index.jsx") == .typescript)
        #expect(SyntaxLanguage.language(forPath: "Podfile") == .ruby)
        // The files commands hand to an editor have no extension.
        let rebase = ".git/worktrees/agent/rebase-merge/git-rebase-todo"
        #expect(SyntaxLanguage.language(forPath: rebase) == .gitRebaseTodo)
        #expect(SyntaxLanguage.language(forPath: ".git/COMMIT_EDITMSG") == .gitMessage)
    }

    @Test
    func `highlights a rebase todo's commands, commits and instructions`() {
        let line = "pick a1b2c3d Keep a worktree listed"
        let tokens = SyntaxHighlighter.highlight(line: line, language: .gitRebaseTodo)
        #expect(tokens.map(\.text).joined() == line)
        #expect(tokens.first == SyntaxToken(kind: .keyword, text: "pick"))
        #expect(tokens.contains(SyntaxToken(kind: .number, text: "a1b2c3d")))
        #expect(tokens.contains { $0.kind == .plain && $0.text.contains("Keep a worktree listed") })

        let instruction = "# Commands:"
        #expect(SyntaxHighlighter.highlight(line: instruction, language: .gitRebaseTodo)
            == [SyntaxToken(kind: .comment, text: instruction)])

        // A label is not a commit, and an unknown first word is not a
        // command, so neither is coloured as one.
        let label = SyntaxHighlighter.highlight(line: "label onto", language: .gitRebaseTodo)
        #expect(label.first == SyntaxToken(kind: .keyword, text: "label"))
        #expect(label.contains { $0.kind == .number } == false)
        let broken = SyntaxHighlighter.highlight(line: "picky a1b2c3d Work", language: .gitRebaseTodo)
        #expect(broken.contains { $0.kind == .keyword } == false)
    }

    @Test
    func `highlights only the block git strips from a commit message`() {
        let subject = "Keep a worktree listed while it is detached"
        #expect(SyntaxHighlighter.highlight(line: subject, language: .gitMessage)
            == [SyntaxToken(kind: .plain, text: subject)])
        // An apostrophe must not open a string that swallows the rest
        // of the line, as the general tokenizer would have it.
        let body = "- git's own listing hides it"
        #expect(SyntaxHighlighter.highlight(line: body, language: .gitMessage)
            == [SyntaxToken(kind: .plain, text: body)])
        let comment = "# Please enter the commit message for your changes."
        #expect(SyntaxHighlighter.highlight(line: comment, language: .gitMessage)
            == [SyntaxToken(kind: .comment, text: comment)])
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
