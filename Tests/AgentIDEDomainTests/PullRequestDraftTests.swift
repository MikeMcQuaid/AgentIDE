import AgentIDEDomain
import Testing

/// Exercises the draft file shape pull requests are edited in: the
/// composed template, the checkbox ticking, the AI disclosure fill
/// and the parse back into a title and body.
struct PullRequestDraftTests {
    @Test
    func `composes the title over the template with checkboxes ticked`() {
        let template = """
        ## Summary

        - [ ] Tests added
          * [ ] Docs updated
        - [x] Already done
        no box [ ] here
        """
        let draft = PullRequestDraft.compose(title: "Fix the crash", template: template, disclosure: nil)
        #expect(draft.hasPrefix("Fix the crash\n\n## Summary"))
        #expect(draft.contains("- [x] Tests added"))
        #expect(draft.contains("  * [x] Docs updated"))
        #expect(draft.contains("no box [ ] here"))
    }

    @Test
    func `fills an AI disclosure heading, label or checkbox`() {
        let heading = PullRequestDraft.compose(
            title: "T",
            template: "## AI disclosure\n\nOther text",
            disclosure: "Claude Code, model fable",
        )
        #expect(heading.contains("## AI disclosure\nClaude Code, model fable\n"))

        let label = PullRequestDraft.compose(
            title: "T",
            template: "AI usage:",
            disclosure: "Claude Code",
        )
        #expect(label.contains("AI usage:\nClaude Code"))

        let checkbox = PullRequestDraft.compose(
            title: "T",
            template: "- [ ] Written with AI assistance",
            disclosure: "Claude Code",
        )
        #expect(checkbox.contains("- [x] Written with AI assistance: Claude Code"))

        let none = PullRequestDraft.compose(
            title: "T",
            template: "Nothing to maintain here",
            disclosure: "Claude Code",
        )
        #expect(none.contains("Claude Code") == false)
    }

    @Test
    func `parses the first line as the title and the rest as the body`() {
        let (title, body) = PullRequestDraft.parse("Fix the crash\n\nA body\nwith lines\n")
        #expect(title == "Fix the crash")
        #expect(body == "A body\nwith lines")

        let (only, empty) = PullRequestDraft.parse("Just a title")
        #expect(only == "Just a title")
        #expect(empty.isEmpty)
    }

    @Test
    func `disclosures join the known parts and vanish when empty`() {
        #expect(
            PullRequestDraft.disclosure(agent: "Claude Code", model: "claude-fable-5", effort: "xhigh")
                == "Claude Code, model claude-fable-5, xhigh effort",
        )
        #expect(PullRequestDraft.disclosure(agent: nil, model: "m", effort: "") == "model m")
        #expect(PullRequestDraft.disclosure(agent: nil, model: nil, effort: nil) == nil)
        #expect(PullRequestDraft.disclosure(agent: "", model: "", effort: "") == nil)
    }
}
