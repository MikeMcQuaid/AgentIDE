import AgentIDEData
import AgentIDEDomain
import Foundation
@testable import PRFeature
import TerminalUI
import Testing

/// Opening a pull request tells the sidebar at once: both surfaces
/// read one per-branch cache, so the row learns the number and state
/// without waiting for a poll. Split from the model tests for length.
extension PullRequestsModelTests {
    @Test
    func `the draft toggle opens a draft and is remembered`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 0)])
        var openedAsDraft = false
        model.performCreate = { _, _, _, _, isDraft in
            openedAsDraft = isDraft
            return "https://github.com/o/r/pull/42"
        }
        await model.reload()
        model.prTitle = "A change"
        model.prIsDraft = true

        #expect(await model.createPullRequest())

        // What the form said reaches `gh`, and the row shows the
        // draft's own glyph before any fetch has been near it.
        #expect(openedAsDraft)
        #expect(model.selected?.isDraft == true)
    }

    @Test
    func `opening a pull request lands it in the shared branch cache`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 1)])
        model.performCreate = { _, _, _, _, _ in "https://github.com/o/r/pull/42" }
        model.prTitle = "A change"
        await model.reload()
        let before = UserDefaults.standard.integer(forKey: UtilityTabTarget.pullRequestCacheKey)

        #expect(await model.createPullRequest())

        // The row reads this, so it paints the moment the form is
        // answered rather than at the next poll.
        let cached = model.pullRequests.branchSummary(repositoryPath: model.repository.path, branch: "feature")
        #expect(cached?.number == 42)
        #expect(cached?.state == "OPEN")
        #expect(cached?.headBranch == "feature")
        // And the sidebar is told to repaint from it.
        #expect(UserDefaults.standard.integer(forKey: UtilityTabTarget.pullRequestCacheKey) > before)
    }

    @Test
    func `the listing's own answer beats the one the form assembled`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 1)])
        model.performCreate = { _, _, _, _, _ in "https://github.com/o/r/pull/42" }
        // GitHub has it already: its answer carries the checks and
        // mergeability the form could not know.
        let listed = PullRequestSummary(
            number: 42,
            title: "A change",
            url: "https://github.com/o/r/pull/42",
            headBranch: "feature",
            mergeable: "MERGEABLE",
            reviewDecision: "",
            checks: "SUCCESS",
            baseBranch: "main",
            state: "OPEN",
        )
        model.fetchList = { _, _ in [listed] }
        model.prTitle = "A change"

        #expect(await model.createPullRequest())
        let cached = model.pullRequests.branchSummary(repositoryPath: model.repository.path, branch: "feature")
        #expect(cached?.checks == "SUCCESS")
        #expect(cached?.mergeable == "MERGEABLE")
    }
}
