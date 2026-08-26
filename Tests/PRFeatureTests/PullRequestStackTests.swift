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
    func `each stack entry fills its form from its own commits and waits on the branch below`() async {
        // The tab is for the `feature` worktree the fixture names,
        // which is what the stack's checked-out branch is here.
        let fixtures = PullRequestsModelTests()
        let model = fixtures.makeModel(items: [fixtures.item(branch: "feature", ahead: 1)])
        model.fetchCurrentBranch = { _ in "upper" }
        model.stacking.fetch = { _ in
            BranchStack(base: "main", branches: ["lower", "upper"], checkedOut: "upper")
        }
        model.stacking.unpushed = { _ in ["lower"] }
        let ranges = Mutex([String?]())
        model.fetchCommitMessages = { _, range in
            ranges.withLock { $0.append(range) }
            return range == "main..lower" ? ["Lower work\n\nWhy lower."] : ["Upper work\n\nWhy upper."]
        }
        await model.reload()

        // The checked-out top entry: its own span, blocked by the
        // unpushed branch under it.
        #expect(model.listedRange == "lower..upper")
        #expect(model.prTitle == "Upper work")
        #expect(model.unpushedBelow == "lower")

        // Moving down: the bottom entry's span, nothing under it.
        model.clearDraft()
        model.show(branch: "lower")
        try? await Task.sleep(for: .milliseconds(200))
        #expect(model.listedRange == "main..lower")
        #expect(model.prTitle == "Lower work")
        #expect(model.unpushedBelow == nil)
        #expect(ranges.withLock { $0 }.contains("main..lower"))
    }

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
