import AgentIDEData
import AgentIDEDomain
@testable import PRFeature
import Synchronization
import Testing

/// The stack's rebase reads again and then restacks once more for a
/// signed stack, as the lone rebase does.
extension PullRequestStackTests {
    @Test
    func `a stack read too early is read again, not restacked again`() async {
        let fixtures = PullRequestsModelTests()
        let model = fixtures.makeModel(items: [fixtures.item(branch: "feature", ahead: 1)])
        model.fetchCurrentBranch = { _ in "upper" }
        let stack = BranchStack(base: "main", branches: ["lower", "upper"], checkedOut: "upper")
        let restacks = Mutex(0)
        let readsAfterRestack = Mutex(0)
        model.stacking.facts = { _ in
            guard restacks.withLock({ $0 }) > 0 else {
                return StackFacts(stack: stack)
            }

            return readsAfterRestack.withLock { reads in
                reads += 1
                return StackFacts(stack: stack, unsigned: reads >= 2 ? [] : ["lower"])
            }
        }
        model.stacking.restack = { _ in
            restacks.withLock { $0 += 1 }
            return ["upper"]
        }
        // The rebase pushes the stack after; nothing real to push here.
        model.stacking.push = { _ in [] }
        await model.reload()

        #expect(await model.rebaseSigned())
        #expect(restacks.withLock { $0 } == 1)
    }

    @Test
    func `a stack still unsigned after a restack and a second read is restacked once more`() async {
        let fixtures = PullRequestsModelTests()
        let model = fixtures.makeModel(items: [fixtures.item(branch: "feature", ahead: 1)])
        model.fetchCurrentBranch = { _ in "upper" }
        let stack = BranchStack(base: "main", branches: ["lower", "upper"], checkedOut: "upper")
        let restacks = Mutex(0)
        model.stacking.facts = { _ in
            StackFacts(stack: stack, unsigned: restacks.withLock { $0 } >= 2 ? [] : ["lower"])
        }
        model.stacking.restack = { _ in
            restacks.withLock { $0 += 1 }
            return ["upper"]
        }
        // The rebase pushes the stack after; nothing real to push here.
        model.stacking.push = { _ in [] }
        await model.reload()

        #expect(await model.rebaseSigned())
        #expect(restacks.withLock { $0 } == 2)

        // Still unsigned after two, and it is the key's turn.
        model.stacking.facts = { _ in StackFacts(stack: stack, unsigned: ["lower"]) }
        restacks.withLock { $0 = 0 }
        #expect(await model.rebaseSigned() == false)
        #expect(restacks.withLock { $0 } == 2)
    }
}
