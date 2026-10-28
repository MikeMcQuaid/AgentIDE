@testable import PRFeature
import SanductorData
import SanductorDomain
import Synchronization
import Testing

/// Merging from the bottom of a stack. Split from the stack tests
/// for length.
extension PullRequestStackTests {
    @Test(arguments: [
        (GitHubClient.MergeResult.pending, "Requested the stack merge."),
        (.merged, "Merged the stack."),
        (.enqueued, "Queued the stack."),
    ])
    func `the bottom of a stack merges through the stack`(outcome: GitHubClient.MergeResult, status: String) async {
        let fixtures = PullRequestsModelTests()
        let model = fixtures.makeModel(items: [fixtures.item(branch: "feature", ahead: 1)])
        model.fetchCurrentBranch = { _ in "lower" }
        model.stacking.facts = { _ in
            StackFacts(stack: BranchStack(base: "main", branches: ["lower", "upper"], checkedOut: "lower"))
        }
        await model.reload()
        model.pullRequests.rememberListing(
            repositoryPath: model.repository.path,
            scope: .branch("lower"),
            summaries: [fixtures.summary(1, head: "lower", base: "main")],
        )

        // Even the bottom entry must link the stack before merging.
        #expect(model.listedParent == nil)
        #expect(model.isInStack)
        #expect(model.canMergeStack)

        let done = Mutex([String]())
        model.performLinkStack = { _ in done.withLock { $0.append("link") } }
        model.performMergeStack = { _, number in
            done.withLock { $0.append("merge " + String(number)) }
            return outcome
        }
        model.selected = fixtures.summary(1, head: "lower", base: "main", mergeable: "MERGEABLE", checks: "SUCCESS")
        #expect(await model.performMergeAction())
        #expect(done.withLock { $0 } == ["link", "merge 1"])
        #expect(model.status == status)
        #expect(model.pullRequests.mergeRequestedRecently(repositoryPath: "/repo", branch: "lower"))
        #expect(model.pullRequests.mergeRequestedRecently(repositoryPath: "/repo", branch: "upper") == false)
    }
}
