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
}
