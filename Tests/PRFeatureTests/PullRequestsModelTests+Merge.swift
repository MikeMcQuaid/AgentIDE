import AgentIDEDomain
@testable import PRFeature
import Testing

/// The merge button says Merge only for a pull request GitHub
/// would merge now; a review still outstanding makes it Automerge,
/// which is what GitHub's own refusal asks for.
extension PullRequestsModelTests {
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
        var cleaned = false
        model.performPostMergeCleanup = { _, _ in cleaned = true }
        model.selected = reviewed
        #expect(model.mergeActionTitle == "Automerge")
        await model.performMergeAction()
        #expect(cleaned == false)
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
        var cleaned = false
        model.performPostMergeCleanup = { _, _ in cleaned = true }
        model.selected = draft

        // Everything else about it says merge, and GitHub would
        // refuse both that and automerge: "Pull Request is still a
        // draft". The button says the step that has to come first.
        #expect(model.mergeActionTitle == "Mark ready")
        #expect(model.mergeActionBusyTitle == "Marking ready")
        #expect(PullRequestsModel.isReadyToMerge(draft) == false)

        await model.performMergeAction()
        // Nothing merged, so nothing is cleaned up behind it.
        #expect(cleaned == false)
    }

    @Test
    func `a merge queue waits rather than asking for automerge`() {
        let waiting = PullRequestSummary(
            number: 23_703,
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
        model.selected = waiting
        model.hasMergeQueue = true

        // GitHub refuses automerge where the queue sets the merge
        // strategy: "Auto-merge is not supported for stacked pull
        // requests", and the strategy is the queue's. The button
        // says what the queue will take, and waits for it.
        #expect(model.mergeActionTitle == "Queue")
        #expect(model.mergeActionBusyTitle == "Queueing")
        #expect(model.canMergeAction == false)

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
