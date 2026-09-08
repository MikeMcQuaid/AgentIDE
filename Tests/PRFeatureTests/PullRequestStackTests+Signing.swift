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
        model.stacking.fetch = { _ in
            BranchStack(base: "main", branches: ["lower", "upper"], checkedOut: "upper")
        }
        let restacks = Mutex(0)
        let readsAfterRestack = Mutex(0)
        model.stacking.restack = { _ in
            restacks.withLock { $0 += 1 }
            return ["upper"]
        }
        model.stacking.unsigned = { _ in
            guard restacks.withLock({ $0 }) > 0 else {
                return []
            }

            return readsAfterRestack.withLock { reads in
                reads += 1
                return reads >= 2 ? [] : ["lower"]
            }
        }
        await model.reload()

        #expect(await model.rebaseSigned())
        #expect(restacks.withLock { $0 } == 1)
    }

    @Test
    func `a stack still unsigned after a restack and a second read is restacked once more`() async {
        let fixtures = PullRequestsModelTests()
        let model = fixtures.makeModel(items: [fixtures.item(branch: "feature", ahead: 1)])
        model.fetchCurrentBranch = { _ in "upper" }
        model.stacking.fetch = { _ in
            BranchStack(base: "main", branches: ["lower", "upper"], checkedOut: "upper")
        }
        let restacks = Mutex(0)
        model.stacking.restack = { _ in
            restacks.withLock { $0 += 1 }
            return ["upper"]
        }
        model.stacking.unsigned = { _ in restacks.withLock { $0 } >= 2 ? [] : ["lower"] }
        await model.reload()

        #expect(await model.rebaseSigned())
        #expect(restacks.withLock { $0 } == 2)

        // Still unsigned after two, and it is the key's turn.
        model.stacking.unsigned = { _ in ["lower"] }
        restacks.withLock { $0 = 0 }
        #expect(await model.rebaseSigned() == false)
        #expect(restacks.withLock { $0 } == 2)
    }
}
