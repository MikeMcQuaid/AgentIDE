import AgentIDEDomain
import Testing

/// Exercises the copy reflow that makes terminal yanks paste
/// cleanly into prose tools.
struct PasteableTextTests {
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
        #expect(PasteableText.reflow("\u{258E} first line\n\u{258E} second line") == "first line second line")
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
    func `prose that merely mentions a flag still reflows`() {
        let prose = """
        ▎ You can pass --verbose to see more, and the wrapped line
        ▎ continues here as ordinary explanation of the option.
        """
        #expect(PasteableText.reflow(prose).contains("\n") == false)
        #expect(PasteableText.looksLikeCode(["one plain sentence", "another plain sentence"]) == false)
    }
}
