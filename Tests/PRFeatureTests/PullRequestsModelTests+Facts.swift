import Foundation
@testable import PRFeature
import SanductorData
import SanductorDomain
import Synchronization
import Testing

/// The worktree facts (signing, rebase need) must land even when a
/// stack read overlaps them; split from the model tests for length.
@MainActor
extension PullRequestsModelTests {
    @Test
    func `a reload supersedes the queued sidebar refresh`() async {
        let model = makeModel(items: [item(branch: "main", ahead: 2)])
        model.currentBranch = "main"
        var stackReads = 0
        model.stacking.facts = { worktree in
            stackReads += 1
            return StackFacts(stack: BranchStack(base: nil, branches: [worktree.branch], checkedOut: worktree.branch))
        }
        await model.reload()
        #expect(model.isDefaultBranch)

        stackReads = 0
        model.currentBranch = "feature"
        model.items = [item(branch: "feature", ahead: 2)]
        await model.reload()
        for _ in 0 ..< 10 {
            await Task.yield()
        }

        #expect(stackReads == 1)
        #expect(model.isDefaultBranch == false)
        #expect(model.canPush)
    }

    @Test
    func `an older stack read cannot restart branch fact gathering`() async {
        let worktreeItem = item(branch: "feature", ahead: 1)
        let model = makeModel(items: [worktreeItem])
        let waiting = Mutex<CheckedContinuation<StackFacts, Never>?>(nil)
        let facts = StackFacts(stack: BranchStack(base: "main", branches: ["feature"], checkedOut: "feature"))
        var stackReads = 0
        model.stacking.facts = { _ in
            stackReads += 1
            if stackReads == 1 {
                return await withCheckedContinuation { continuation in waiting.withLock { $0 = continuation } }
            }
            return facts
        }
        var factReads = 0
        model.fetchRebaseNeed = { _ in
            factReads += 1
            return factReads == 1 ? .rebase : .nothing
        }
        let older = Task {
            await model.refreshWorktreeFacts(worktreeItem.worktree)
        }
        while waiting.withLock({ $0 == nil }) {
            await Task.yield()
        }
        await model.refreshWorktreeFacts(worktreeItem.worktree)
        #expect(model.rebaseNeed == .rebase)

        waiting.withLock { $0 }?.resume(returning: facts)
        await older.value

        #expect(factReads == 1)
        #expect(model.rebaseNeed == .rebase)
    }

    @Test
    func `a stack read overlapping the facts does not discard them`() async {
        let worktreeItem = item(branch: "feature", ahead: 1)
        let model = makeModel(items: [worktreeItem])
        let gathering = Mutex(false)
        model.fetchRebaseNeed = { _ in
            gathering.withLock { $0 = true }
            try? await Task.sleep(for: .milliseconds(200))
            return .sign
        }
        async let facts: Void = model.refreshWorktreeFacts(worktreeItem.worktree)
        // Only once the facts are mid-gather does a poll's stack
        // read overlap them, which is the real race.
        while gathering.withLock({ $0 }) == false {
            try? await Task.sleep(for: .milliseconds(5))
        }
        await model.loadStack()
        await facts
        #expect(model.rebaseNeed == .sign)
        #expect(model.canRebase)
    }
}
