import AgentIDEData
import AgentIDEDomain
@testable import PRFeature
import Testing

/// The AI disclosure the pull request form writes into a template's
/// own section, which is what the Homebrew repositories ask for.
struct PullRequestDisclosureTests {
    // MARK: Internal

    @Test
    func `the disclosure goes in the template's own section, once`() {
        let sentence = "Claude Code with Opus-5 at Extra High effort, with local review and testing."
        let ticked = PullRequestsModel.disclosing(in: Self.homebrewTemplate, sentence: sentence)
        let template = try? #require(ticked)
        #expect(template?.contains("- [x] I did not use AI/LLM") == true)
        #expect(template?.contains(sentence) == true)

        // Said once however often the button is pressed.
        let again = PullRequestsModel.disclosing(
            in: template ?? "",
            sentence: "Codex CLI with GPT 5.6-sol at Minimal effort, with local review and testing.",
        )
        #expect(again?.contains("Claude Code") == false)
        #expect(again?.contains("Codex CLI with GPT 5.6-sol at Minimal effort") == true)

        // A template with no AI section is left alone, so the
        // sentence goes in the body instead.
        #expect(PullRequestsModel.disclosing(in: "- [ ] Tested?", sentence: "x") == nil)
    }

    @Test
    func `what a session was started with reads as the pickers write it`() {
        let claude = "--model opus-5 --effort xhigh"
        #expect(PullRequestsModel.model(inArguments: claude) == "opus-5")
        #expect(PullRequestsModel.effort(inArguments: claude) == "xhigh")

        let codex = "--model gpt-5.6-sol -c model_reasoning_effort=minimal"
        #expect(PullRequestsModel.model(inArguments: codex) == "gpt-5.6-sol")
        #expect(PullRequestsModel.effort(inArguments: codex) == "minimal")

        #expect(PullRequestsModel.model(inArguments: "") == nil)
        #expect(PullRequestsModel.effort(inArguments: "") == nil)
        #expect(AgentOptionName.display("xhigh") == "Extra High")
        #expect(AgentOptionName.display("gpt-5.6-sol") == "GPT 5.6-sol")
        #expect(AgentOptionName.display("opus-5") == "Opus-5")
    }

    // MARK: Private

    /// The shape Homebrew's own template has, trimmed to the part
    /// that matters here.
    private static let homebrewTemplate = """
    - [ ] Have you followed our Contributing guidelines?

    -----

    - [ ] I did not use AI/LLM to create this PR, or I disclosed the tool/model below.

    <!-- If AI was used, explain below how it was used and how you verified the changes. -->

    -----
    """
}
