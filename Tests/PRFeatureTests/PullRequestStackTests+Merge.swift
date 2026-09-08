import AgentIDEData
import AgentIDEDomain
@testable import PRFeature
import Synchronization
import Testing

/// Merging from the bottom of a stack. Split from the stack tests
/// for length.
extension PullRequestStackTests {
    @Test
    func `the bottom of a stack merges through the stack`() async {
        let fixtures = PullRequestsModelTests()
        let model = fixtures.makeModel(items: [fixtures.item(branch: "feature", ahead: 1)])
        model.fetchCurrentBranch = { _ in "lower" }
        model.stacking.fetch = { _ in
            BranchStack(base: "main", branches: ["lower", "upper"], checkedOut: "lower")
        }
        await model.reload()
        model.pullRequests.rememberListing(
            repositoryPath: model.repository.path,
            scope: .branch("lower"),
            summaries: [fixtures.summary(1, head: "lower", base: "main")],
        )

        // Nothing below it to wait on, and never the lone pull
        // request's merge: on a merge queue gh joins the queue
        // through auto-merge, which GitHub refuses for a stacked
        // pull request, so queueing the bottom failed.
        #expect(model.isStackedEntry == false)
        #expect(model.isInStack)
        #expect(model.canMergeStack)

        let done = Mutex([String]())
        model.performLinkStack = { _ in done.withLock { $0.append("link") } }
        model.performMergeStack = { _, number in done.withLock { $0.append("merge " + String(number)) } }
        model.selected = fixtures.summary(1, head: "lower", base: "main")
        #expect(await model.mergeStack())
        #expect(done.withLock { $0 } == ["link", "merge 1"])
    }
}
