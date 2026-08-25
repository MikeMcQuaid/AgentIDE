import AgentIDEData
import AgentIDEDomain
import Foundation
@testable import PRFeature
import Synchronization
import Testing

/// The pull request tab's view of a stack: which branch it lists,
/// and what its two stack actions would do.
@MainActor
struct PullRequestStackTests {
    // MARK: Internal

    @Test
    func `a stack entry stays listed through the reload that reads the real branch`() async {
        let model = makeModel()
        model.fetchCurrentBranch = { _ in "upper" }
        model.stacking.fetch = { _ in
            BranchStack(base: "main", branches: ["lower", "upper"], checkedOut: "upper")
        }
        let asked = Mutex([String]())
        model.fetchList = { scope, _ in
            if case let .branch(branch) = scope {
                asked.withLock { $0.append(branch) }
            }
            return []
        }
        await model.reload()

        model.show(branch: "lower")
        try? await Task.sleep(for: .milliseconds(100))

        // Listing a lower entry asks about that branch, and keeps
        // asking about it: the reload reads which branch is really
        // checked out, which used to overwrite the choice.
        #expect(model.listedBranch == "lower")
        #expect(asked.withLock { $0 }.last == "lower")
        await model.reload(keepingSelection: true)
        #expect(model.listedBranch == "lower")

        // Back to the branch the worktree holds.
        model.show(branch: "upper")
        try? await Task.sleep(for: .milliseconds(100))
        #expect(model.listedBranch == "upper")
    }

    // MARK: Private

    private func makeModel() -> PullRequestsModel {
        PullRequestsModelTests().makeModel()
    }
}
