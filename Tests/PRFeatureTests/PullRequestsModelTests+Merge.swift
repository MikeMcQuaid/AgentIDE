import AgentIDEData
import AgentIDEDomain
@testable import PRFeature
import Testing

/// The merge button says Merge only for a pull request GitHub
/// would merge now; a review still outstanding offers automerge,
/// which is what GitHub's own refusal asks for.
extension PullRequestsModelTests {
    @Test(arguments: [GitHubClient.MergeResult.pending, .merged, .enqueued])
    func `requesting a merge leaves cleanup to the poll`(outcome: GitHubClient.MergeResult) async {
        let model = makeModel(items: [item(branch: "feature", ahead: 0)])
        model.selected = summary(7, head: "feature", mergeable: "MERGEABLE", checks: "SUCCESS")
        model.hasMergeQueue = true
        model.performMergeChange = { _ in outcome }

        await model.performMergeAction()

        #expect(model.pullRequests.mergeRequestedRecently(repositoryPath: "/repo", branch: "feature"))
        #expect(model.worktree(on: "feature")?.branch == "feature")
    }

    @Test
    func `a review outstanding turns merge into automerge`() async {
        let reviewed = PullRequestSummary(
            number: 37,
            title: "Awaiting review",
            url: "",
            headBranch: "feature",
            mergeable: "MERGEABLE",
            reviewDecision: "REVIEW_REQUIRED",
            checks: "SUCCESS",
            baseBranch: "main",
            state: "OPEN",
        )
        let model = makeModel(items: [item(branch: "feature", ahead: 0)])
        model.selected = reviewed
        #expect(model.mergeActionTitle == "Automerge")
        await model.performMergeAction()
        #expect(model.pullRequests.mergeRequestedRecently(repositoryPath: "/repo", branch: "feature") == false)
    }

    @Test
    func `a draft is taken out of draft rather than merged`() async {
        let draft = PullRequestSummary(
            number: 45,
            title: "Still a draft",
            url: "",
            headBranch: "feature",
            mergeable: "MERGEABLE",
            reviewDecision: "",
            checks: "SUCCESS",
            baseBranch: "main",
            state: "OPEN",
            isDraft: true,
        )
        let model = makeModel(items: [item(branch: "feature", ahead: 0)])
        model.selected = draft

        // Everything else about it says merge, and GitHub would
        // refuse both that and automerge: "Pull Request is still a
        // draft". The button says the step that has to come first.
        #expect(model.mergeActionTitle == "Ready")
        #expect(model.mergeActionBusyTitle == "Readying")
        #expect(PullRequestsModel.isReadyToMerge(draft) == false)

        await model.performMergeAction()
        #expect(model.pullRequests.mergeRequestedRecently(repositoryPath: "/repo", branch: "feature") == false)
    }

    @Test(arguments: [
        ("MERGEABLE", "PENDING", "APPROVED"),
        ("MERGEABLE", "SUCCESS", "REVIEW_REQUIRED"),
        ("UNKNOWN", "SUCCESS", "APPROVED"),
    ])
    func `a waiting PR can enable automerge with a queue`(mergeable: String, checks: String, review: String) {
        let waiting = PullRequestSummary(
            number: 23_703,
            title: "Awaiting review",
            url: "",
            headBranch: "feature",
            mergeable: mergeable,
            reviewDecision: review,
            checks: checks,
            baseBranch: "main",
            state: "OPEN",
        )
        let model = makeModel(items: [item(branch: "feature", ahead: 0)])
        model.selected = waiting
        model.hasMergeQueue = true

        #expect(model.mergeActionTitle == "Automerge")
        #expect(model.mergeActionBusyTitle == "Enabling")
        #expect(model.canMergeAction)

        // Ready, and it takes it.
        model.selected = PullRequestSummary(
            number: 23_703,
            title: "Reviewed",
            url: "",
            headBranch: "feature",
            mergeable: "MERGEABLE",
            reviewDecision: "APPROVED",
            checks: "SUCCESS",
            baseBranch: "main",
            state: "OPEN",
        )
        #expect(model.mergeActionTitle == "Queue")
        #expect(model.canMergeAction)

        // Without a queue, automerge is still what GitHub asks for.
        model.hasMergeQueue = false
        model.selected = waiting
        #expect(model.mergeActionTitle == "Automerge")
        #expect(model.canMergeAction)
    }
}
