import AgentIDEData
import AgentIDEDomain
@testable import PRFeature
import Testing

extension PullRequestStackTests {
    @Test(arguments: [false, true])
    func `fork stacks disable actions while lone fork branches can still push`(stacked: Bool) async {
        let fixtures = PullRequestsModelTests()
        let model = fixtures.makeModel(items: [fixtures.item(branch: "feature", ahead: 1)])
        model.stacking.fetch = { _ in
            BranchStack(
                base: "main",
                branches: stacked ? ["feature", "upper"] : ["feature"],
                checkedOut: "feature",
                stackingBlocker: "GitHub does not support pull request stacks across forks.",
            )
        }
        model.stacking.pending = { _ in true }
        model.stacking.unpushed = { _ in ["feature"] }
        await model.reload()
        model.pullRequests.rememberListing(
            repositoryPath: model.repository.path,
            scope: .branch("feature"),
            summaries: [fixtures.summary(1, head: "feature", base: "main")],
        )

        #expect(model.canPush == !stacked)
        #expect(model.canRestack == false)
        #expect(model.canPushStack == false)
        #expect(model.isStackLinked)
        #expect(model.isStackBelowReady)
        #expect(model.canMergeStack == false)
        #expect(model.pushStackHelp == model.stack.stackingBlocker)
    }
}
