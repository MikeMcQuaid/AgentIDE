import AgentIDEData
import Foundation
@testable import PRFeature
import Synchronization
import Testing

/// The worktree facts (signing, rebase need) must land even when a
/// stack read overlaps them; split from the model tests for length.
extension PullRequestsModelTests {
    @Test
    @MainActor
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
