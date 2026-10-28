import SanductorDomain
import Testing

/// Exercises the copy reflow that makes terminal yanks paste
/// cleanly into prose tools.
struct PasteableTextTests {
    @Test(arguments: [
        "\u{061C}", "\u{200E}", "\u{200F}",
        "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}",
        "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}",
    ])
    func `terminal copies remove bidirectional formatting controls`(control: String) {
        let text = "echo left" + control + "right"
        #expect(PasteableText.cleanTerminalCopy(text) == "echo leftright")
        #expect(PasteableText.reflow(text) == "echo leftright")
    }

    @Test
    func `terminal cleanup removes hidden controls and row padding`() {
        let text = "\u{FEFF}  first\u{0}word\u{07}\u{7F}\u{85}  \r\n\tsecond\u{200B}\t \rthird  "
        #expect(PasteableText.cleanTerminalCopy(text) == "  first word\n\tsecond\nthird")
    }

    @Test
    func `terminal cleanup preserves meaningful spacing and Unicode`() {
        let text = "\tlet café = \"👩‍💻 ❤️ می\u{200C}روم\"\n    left    right\n\n"
        #expect(PasteableText.cleanTerminalCopy(text) == text)
    }

    @Test
    func `hidden cells cannot defeat prose and gutter cleanup`() {
        #expect(PasteableText.reflow("\u{0}\u{0}▎\u{0}Hello\u{0}world\u{07}  ") == "Hello world")
        let wrapped = "  Hello\u{0}world  \r\n\u{0}wrapped\u{200B} text  "
        #expect(PasteableText.reflow(wrapped) == "Hello world wrapped text")
    }

    @Test
    func `joins hard-wrapped lines and keeps paragraphs apart`() {
        let wrapped = """
          The agent finished the refactor and moved the tests
          into their own target so they run in parallel.

          A second paragraph survives the reflow.
        """
        #expect(
            PasteableText.reflow(wrapped) == "The agent finished the refactor and moved the tests "
                + "into their own target so they run in parallel."
                + "\n\nA second paragraph survives the reflow.",
        )
    }

    @Test
    func `list items keep their own lines and swallow their wraps`() {
        let list = """
        Changes:
        - first item wraps onto
          a second terminal line
        - second item
        1. numbered too
        """
        #expect(
            PasteableText.reflow(list) == "Changes:"
                + "\n\n- first item wraps onto a second terminal line"
                + "\n- second item"
                + "\n1. numbered too",
        )
    }

    @Test
    func `single lines only lose surrounding whitespace`() {
        #expect(PasteableText.reflow("  one line  ") == "one line")
        #expect(PasteableText.reflow("  git status  \n") == "git status")
    }

    @Test
    func `gutter marks trim from lines and single copies`() {
        #expect(PasteableText.strippingGutter("\u{258E} hello") == "hello")
        #expect(PasteableText.strippingGutter("\u{258E}\u{258E} nested") == "nested")
        // Two lowercase lines prove nothing about being prose, so
        // they are kept as copied, gutter marks gone.
        #expect(PasteableText.reflow("\u{258E} first line\n\u{258E} second line") == "first line\nsecond line")
        #expect(PasteableText.reflow("\u{258E} First line\n\u{258E} second line") == "First line second line")
        #expect(PasteableText.reflow("  \u{258E} one liner  ") == "one liner")
    }

    @Test
    func `blank runs collapse to one paragraph break`() {
        #expect(PasteableText.reflow("a\n\n\n\nb") == "a\n\nb")
    }

    @Test
    func `command blocks keep their lines instead of flowing together`() {
        // The exact shape that once pasted as one broken line: a
        // rectangle copy of an agent's suggested commands.
        let script = """
        ▎ cd /Users/Shared/sv-mike/worktrees/64f574f9/administrate-sentry-audit
        ▎ git fetch --prune
        ▎ git checkout sentry-errors-aug-16-backend
        ▎ git rebase --gpg-sign --force-rebase origin/HEAD
        ▎ git push -u origin sentry-errors-aug-16-backend sentry-errors-aug-16-integrations \\
        ▎   sentry-errors-aug-16-legacy-ui sentry-errors-aug-16-workspaces
        """
        let reflowed = PasteableText.reflow(script)
        #expect(reflowed.split(separator: "\n").count == 6)
        let firstTwo = "cd /Users/Shared/sv-mike/worktrees/64f574f9/administrate-sentry-audit\ngit fetch --prune"
        #expect(reflowed.hasPrefix(firstTwo))
        #expect(reflowed.contains("\\\nsentry-errors-aug-16-legacy-ui"))
    }

    @Test
    func `commands keep their lines even when prose surrounds them`() {
        // The copy that prompted this: an answer explaining what to
        // run, the commands, then more explanation. Judged over the
        // whole copy the prose outvoted the commands and the script
        // came out as one unrunnable line.
        let answer = """
        ▎ Rebase both branches onto trunk and force push them, which
        ▎ is safe here because nobody else has them:
        ▎ cd $A
        ▎ git fetch origin
        ▎ git checkout sentry-errors-aug-18-backend
        ▎ git rebase --gpg-sign --force-rebase origin/trunk
        ▎ git push --force-with-lease -u origin sentry-errors-aug-18-backend
        ▎ Then check the pull requests still show the right base
        ▎ branch before merging either of them.
        """
        let reflowed = PasteableText.reflow(answer)
        #expect(reflowed.hasPrefix("Rebase both branches onto trunk and force push them, which is safe here"))
        #expect(reflowed.contains("cd $A\ngit fetch origin\ngit checkout sentry-errors-aug-18-backend"))
        #expect(reflowed.contains("origin/trunk\ngit push --force-with-lease -u origin"))
        let closing = "Then check the pull requests still show the right base branch "
            + "before merging either of them."
        #expect(reflowed.hasSuffix(closing))
    }

    @Test
    func `lowercase lines are kept as copied rather than joined`() {
        // Commands, paths and flags open in lowercase; the doubt goes
        // to keeping the line, since a sentence left wrapped is
        // untidy and a command wrongly joined is broken.
        let commands = """
        brew install foo
        cd ~/src
        make test
        """
        #expect(PasteableText.reflow(commands) == commands)
    }

    @Test
    func `a line that mentions a flag is kept as copied, not joined`() {
        // The doubt goes to keeping the line: a sentence that names
        // a flag might be the command itself, and a command wrongly
        // joined is broken where a sentence left wrapped is untidy.
        let prose = """
        ▎ You can pass --verbose to see more, and the wrapped line
        ▎ continues here as ordinary explanation of the option.
        """
        #expect(PasteableText.reflow(prose).contains("\n"))
    }
}
