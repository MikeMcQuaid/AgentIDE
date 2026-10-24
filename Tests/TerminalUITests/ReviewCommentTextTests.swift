import AgentIDEDomain
@testable import TerminalUI
import Testing

@MainActor
struct ReviewCommentTextTests {
    @Test(arguments: ReviewBot.allCases)
    func `bot command clutter is hidden without removing findings`(_ bot: ReviewBot) {
        let body = """
        [Review in Change Stack →](https://example.com/stack)

        <details><summary>Summary</summary>
        Keep this finding.
        </details>

        - [ ] **Autofix** · Keep fixing CodeRabbit findings and required CI, and resolving merge conflicts.

        <sub>Comment `@coderabbitai help` to get the list of available commands.</sub>
        """
        let shown = ReviewCommentText(body, author: bot.login).text
        #expect(shown.contains("Review in Change Stack") == false)
        #expect(shown.contains("Autofix") == false)
        #expect(shown.contains("available commands") == false)
        #expect(shown.contains("<details><summary>Summary</summary>\nKeep this finding.\n</details>"))
        #expect(ReviewCommentText(body, author: "reviewer").text == body)
    }

    @Test
    func `bot code examples and other tasks are unchanged`() {
        let body = """
        ```markdown
        Comment @coderabbitai help to get the list of available commands.
        [Review in Change Stack →](https://example.com/stack)
        - [ ] Autofix · Keep fixing CodeRabbit findings and required CI, and resolving merge conflicts.
        ```

        - [ ] Keep this task.
        We should discuss Autofix and Review in Change Stack → here.
        """
        #expect(ReviewCommentText(body, author: "coderabbitai").text == body)
    }

    @Test
    func `billing callouts and receipts disappear without hiding findings`() {
        let notice = """
        > [!NOTE]
        > This review was completed with usage-based billing: files reviewed beyond your plan's included limits \
        are billed at $0.25/file. [View usage-based billing](https://example.com/billing).
        """
        let body = """
        Keep this finding.

        \(notice)

        <details><summary>Usage-based review receipt</summary>

        - **Mode:** Continue automatically
        - **Reviewed files:** 1
        - **Charged:** $0.25
        - [View usage details](https://example.com/receipt)
        </details>

        \(notice)

        > [!NOTE]
        > Keep this note.

        <details><summary>Findings</summary>Keep these details.</details>
        """
        let shown = ReviewCommentText(body, author: "coderabbitai[bot]").text
        #expect(shown.contains("billing") == false)
        #expect(shown.contains("receipt") == false)
        #expect(shown.contains("$0.25") == false)
        #expect(shown.contains("Keep this finding."))
        #expect(shown.contains("> [!NOTE]\n> Keep this note."))
        #expect(MarkdownTestSupport.kinds(MarkdownText.content(shown)).contains(.blockQuote))
        #expect(shown.contains("Keep these details."))
        let details = MarkdownText.parsedChunks(shown).filter { $0.detailsSummary != nil }
        #expect(details.count == 1)
        #expect(ReviewCommentText(body, author: "reviewer").text == body)
        let example = "```markdown\n" + body + "\n```"
        #expect(ReviewCommentText(example, author: "coderabbitai").text == example)
    }

    @Test(arguments: ReviewBot.allCases, ["999b0", "`999b0`"])
    func `bot commit references stay as written`(_ bot: ReviewBot, hash: String) {
        let body = "<details><summary>Commits reviewed up to " + hash + "</summary>Finding.</details>"
        let shown = ReviewCommentText(body, author: bot.login).text
        #expect(shown == body)
        #expect(ReviewCommentText(body, author: "reviewer").text == body)
    }

    @Test(arguments: ["R&amp;D", "R&#38;D", "R&D"])
    func `receipts with different entity spellings are removed`(_ receiptText: String) {
        let retained = "> Keep R&#38;D and R&D unchanged."
        let body = retained + "\n\n<details><summary>Usage-based review receipt</summary>"
            + receiptText + "</details>\n\n" + retained
        #expect(ReviewCommentText(body, author: "coderabbitai").text == retained + "\n\n\n\n" + retained)
    }

    @Test
    func `commit examples and existing links stay unchanged`() {
        let body = """
        ```markdown
        up to d904c
        ```
        `commits up to d904c`
        up to [d904c](https://example.com/commit/d904c)
        up to --help
        up to d904cXYZ
        up to 1000 lines
        up to 2024
        up to `1000` lines
        <details><summary>Reviewed up to 1000 lines</summary>Finding.</details>
        """
        #expect(ReviewCommentText(body, author: "coderabbitai").text == body)
    }

    @Test
    func `quoted billing examples are not billing notices`() {
        let body = """
        > ```text
        > This review was completed with usage-based billing: example text.
        > ```

        <blockquote><pre>This review was completed with usage-based billing: example text.</pre></blockquote>
        """
        #expect(ReviewCommentText(body, author: "coderabbitai").text == body)
    }

    @Test
    func `codeRabbit promotions and share disclosures are hidden`() {
        let promotion = """
        Thanks for using CodeRabbit! It's free for OSS, and your support helps us grow.
        If you like it, consider giving us a shout-out.
        """
        let body = """
        Keep this finding.

        \(promotion)

        <p>\(promotion)</p>

        [❤️ Share](https://example.com/share)

        <details><summary>❤️ Share</summary>
        [Share on social media](https://example.com/share)
        </details>

        <details><summary>Findings</summary>Keep these details.</details>
        """
        let shown = ReviewCommentText(body, author: "coderabbitai").text
        #expect(shown.contains("Thanks for using") == false)
        #expect(shown.contains("shout-out") == false)
        #expect(shown.contains("Share") == false)
        #expect(shown.contains("Keep this finding."))
        #expect(shown.contains("Keep these details."))
        #expect(ReviewCommentText(body, author: "reviewer").text == body)
        #expect(ReviewCommentText(body, author: "copilot-pull-request-reviewer").text == body)
        let example = "```markdown\n" + body + "\n```"
        #expect(ReviewCommentText(example, author: "coderabbitai").text == example)
    }
}
