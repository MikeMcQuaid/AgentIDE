import AgentIDEData
import AgentIDEDomain
@testable import PRFeature
import Synchronization
import Testing

extension PullRequestStackTests {
    @Test(arguments: [false, true])
    func `the combined action pushes a ready or unsigned stack`(unsigned: Bool) async {
        let fixtures = PullRequestsModelTests()
        let model = fixtures.makeModel(items: [fixtures.item(branch: "feature", ahead: 1)])
        let stack = BranchStack(base: "main", branches: ["lower", "upper"], checkedOut: "upper")
        let actions = Mutex([String]())
        model.stacking.facts = { _ in
            StackFacts(
                stack: stack,
                unpushed: actions.withLock { $0.contains("push") } ? [] : ["lower"],
                unsigned: unsigned && actions.withLock { $0.isEmpty } ? ["lower"] : [],
            )
        }
        model.stacking.restack = { _, _ in
            actions.withLock { $0.append("rebase") }
            return ["lower", "upper"]
        }
        model.stacking.push = { worktree in
            #expect(worktree.branch == "lower")
            actions.withLock { $0.append("push") }
            return ["lower"]
        }
        await model.reload()
        #expect(model.canPublish)
        #expect(model.publishTitle == (unsigned ? "Sign and Push" : "Push"))
        #expect(await model.publish())
        #expect(actions.withLock { $0 } == (unsigned ? ["rebase", "push"] : ["push"]))
        #expect(model.isFullyPushed)
        #expect(model.canPublish == false)
        #expect(model.pushDoneTitle == "Pushed")
    }
}
