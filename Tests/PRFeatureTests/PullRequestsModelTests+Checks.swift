import AgentIDEData
import AgentIDEDomain
@testable import PRFeature
import Testing

/// What the tab says about a pull request's checks around a push.
extension PullRequestsModelTests {
    @Test
    func `a push paints the pull request's checks pending at once`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 1)])
        await model.reload()
        let green = PullRequestSummary(
            number: 7,
            title: "Work",
            url: "",
            headBranch: "feature",
            mergeable: "MERGEABLE",
            reviewDecision: "APPROVED",
            checks: "FAILURE",
            failingCheckLinks: ["https://github.com/o/r/actions/runs/1"],
            baseBranch: "main",
            state: "OPEN",
            headCommit: "old",
        )
        model.pullRequests.rememberBranchSummary(green, repositoryPath: model.repository.path, branch: "feature")
        model.summaries = [green]
        model.selected = green
        // GitHub takes a minute to see the commits, and a listing
        // fetched inside it still says what the old run did.
        model.fetchList = { _, _ in [green] }

        // The row and the pane say pending now, and go on saying it
        // through the reload the push triggers.
        #expect(await model.push())
        #expect(model.selected?.checks == "PENDING")
        #expect(model.selected?.hasFailingChecks == false)
        #expect(model.summaries.first?.checks == "PENDING")

        // GitHub has caught up: another head, and its verdict holds.
        let caughtUp = PullRequestSummary(
            number: 7,
            title: "Work",
            url: "",
            headBranch: "feature",
            mergeable: "MERGEABLE",
            reviewDecision: "APPROVED",
            checks: "SUCCESS",
            baseBranch: "main",
            state: "OPEN",
            headCommit: "new",
        )
        model.fetchList = { _, _ in [caughtUp] }
        model.pullRequests.invalidateListings(repositoryPath: model.repository.path)
        await model.reload(keepingSelection: true)
        #expect(model.summaries.first?.checks == "SUCCESS")
    }
}
