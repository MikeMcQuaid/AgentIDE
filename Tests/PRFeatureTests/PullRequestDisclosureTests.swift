import AgentIDEData
import AgentIDEDomain
import Foundation
@testable import PRFeature
import Testing

/// The AI disclosure the pull request form writes into a template's
/// own section, which is what the Homebrew repositories ask for.
@MainActor
struct PullRequestDisclosureTests {
    // MARK: Internal

    @Test
    func `the disclosure goes in the template's own section, once`() {
        let sentence = "Claude Code with opus-5 at Extra High effort, with local review and testing."
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
    func `ticking every box discloses the agent where the template asks`() {
        // Ticking the AI box without saying what wrote the branch
        // is the one lie the button could tell, so it says it.
        let ticked = PullRequestsModel.disclosing(
            in: Self.homebrewTemplate.replacing("- [ ]", with: "- [x]"),
            sentence: "Claude Code with opus-5 at Extra High effort, with local review and testing.",
        )
        #expect(ticked?.contains("- [x] I did not use AI/LLM") == true)
        #expect(ticked?.contains("with local review and testing.") == true)
    }

    @Test
    func `a session started on the picker's defaults discloses those defaults`() {
        let file = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("agentide-disclosure-" + UUID().uuidString + ".json")
            .path
        defer { try? FileManager.default.removeItem(atPath: file) }
        let fixtures = PullRequestsModelTests()
        let model = fixtures.makeModel(items: [fixtures.item(branch: "feature", ahead: 1)], metadataFile: file)
        model.launchChoices = { _ in (["fable", "opus"], "high") }
        // A default launch writes no flags: the arguments are empty.
        var metadata = model.store.load()
        metadata.sessionsByWorktree["/worktrees/feature"] = "agentide--repo--feature--claude"
        metadata.arguments["agentide--repo--feature--claude"] = ""
        model.store.save(metadata)

        #expect(model.disclosure == "Claude with Fable at High effort, with local review and testing.")
    }

    @Test
    func `the session running in the worktree discloses a stack entry`() {
        // Every branch of a stack shares one worktree, and the row
        // already knows which agent is running in it. Reading only
        // the metadata file meant a lost or never-recorded session
        // took the whole button away.
        let fixtures = PullRequestsModelTests()
        let running = AgentSession(
            name: "agentide--repo--feature--claude",
            agent: .claudeCode,
            status: .running,
            workingDirectory: "/worktrees/feature",
            paneID: "p1",
            activity: nil,
            version: nil,
        )
        let model = fixtures.makeModel(items: [fixtures.item(branch: "feature", ahead: 1, session: running)])
        model.launchChoices = { _ in (["fable", "opus"], "high") }

        #expect(model.disclosure == "Claude with Fable at High effort, with local review and testing.")
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
        // Exactly what the picker shows, which for a name carrying
        // digits or dashes is the name itself.
        #expect(AgentOptionName.display("opus-5") == "opus-5")
        #expect(AgentOptionName.display("minimal") == "Minimal")
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
