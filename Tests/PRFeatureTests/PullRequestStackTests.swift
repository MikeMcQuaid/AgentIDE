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
            return range == "origin/HEAD..lower" ? ["Lower work\n\nWhy lower."] : ["Upper work\n\nWhy upper."]
        }
        await model.reload()

        // The tab opens on the first entry that could have a pull
        // request: the bottom one, with nothing under it, rather
        // than the checked-out top, which is blocked by the unpushed
        // branch beneath it.
        #expect(model.listedRange == "origin/HEAD..lower")
        #expect(model.prTitle == "Lower work")
        #expect(model.unpushedBelow == nil)

        // Moving up: the top entry's own span, and the block.
        model.clearDraft()
        model.show(branch: "upper")
        try? await Task.sleep(for: .milliseconds(200))
        #expect(model.listedRange == "lower..upper")
        #expect(model.prTitle == "Upper work")
        #expect(model.unpushedBelow == "lower")
        #expect(ranges.withLock { $0 }.contains("origin/HEAD..lower"))
    }

    @Test
    func `the bottom of a stack is an ordinary branch, and opens a pull request for itself`() async {
        let fixtures = PullRequestsModelTests()
        let model = fixtures.makeModel(items: [fixtures.item(branch: "feature", ahead: 1)])
        // The worktree holds the top branch while the bottom one is
        // being looked at, which is the ordinary way round: reading
        // an entry checks nothing out.
        model.fetchCurrentBranch = { _ in "upper" }
        model.stacking.fetch = { _ in
            BranchStack(base: "main", branches: ["lower", "upper"], checkedOut: "upper")
        }
        let opened = Mutex([String]())
        model.performCreate = { worktree, _, _, _, _ in
            opened.withLock { $0.append(worktree.branch) }
            return "https://example.com/1"
        }
        await model.reload()

        // Nothing above it makes the bottom entry stacked work: it
        // opens against the default branch, so the tab is the plain
        // one branch tab, actions and all.
        #expect(model.listedBranch == "lower")
        #expect(model.listedParent == nil)
        #expect(model.isStackedEntry == false)

        model.prTitle = "Lower work"
        #expect(await model.createPullRequest())
        // The pull request is the listed branch's, not the checked
        // out one's: opening one for `lower` once opened it for
        // `upper`, against `lower`, which GitHub already had.
        #expect(opened.withLock { $0 } == ["lower"])

        model.show(branch: "upper")
        try? await Task.sleep(for: .milliseconds(200))
        #expect(model.listedParent == "lower")
        #expect(model.isStackedEntry)
    }

    @Test
    func `a stacked entry merges only once its chain is open on GitHub`() async {
        let fixtures = PullRequestsModelTests()
        let model = fixtures.makeModel(items: [fixtures.item(branch: "feature", ahead: 1)])
        model.fetchCurrentBranch = { _ in "upper" }
        model.stacking.fetch = { _ in
            BranchStack(base: "main", branches: ["lower", "upper"], checkedOut: "upper")
        }
        await model.reload()
        model.show(branch: "upper")
        try? await Task.sleep(for: .milliseconds(200))

        // Nothing is open yet, so there is no stack on GitHub to
        // merge, whatever the branches say locally.
        #expect(model.isStackedEntry)
        #expect(model.isStackLinked == false)

        // The entry's own pull request is not enough: merging a
        // stack merges everything below it, which must be there.
        remember(model, branch: "upper", fixtures.summary(2, head: "upper", base: "lower"))
        #expect(model.isStackLinked == false)

        remember(model, branch: "lower", fixtures.summary(1, head: "lower", base: "main"))
        #expect(model.isStackLinked)

        // Open is not ready: a stack merges all at once, so the one
        // below must be mergeable, green and approved on its own.
        #expect(model.isStackBelowReady == false)
        #expect(model.canMergeStack == false)
        model.cacheEnriched(fixtures.summary(
            1,
            head: "lower",
            base: "main",
            mergeable: "MERGEABLE",
            checks: "SUCCESS",
        ))
        #expect(model.canMergeStack)

        // Merging links first: a chain GitHub does not hold as a
        // stack must never be merged as one, and a link that fails
        // takes the merge with it.
        let done = Mutex([String]())
        model.performLinkStack = { _ in done.withLock { $0.append("link") } }
        model.performMergeStack = { _, number in done.withLock { $0.append("merge " + String(number)) } }
        model.selected = fixtures.summary(2, head: "upper", base: "lower")
        #expect(await model.mergeStack())
        #expect(done.withLock { $0 } == ["link", "merge 2"])
    }

    @Test
    func `a worktree on a local-only twin lists the branch that has the pull request`() async {
        let fixtures = PullRequestsModelTests()
        let model = fixtures.makeModel(items: [fixtures.item(branch: "feature", ahead: 1)])
        // What a renamed branch leaves behind: the worktree holds a
        // local-only name, and the stack lists the pushed twin that
        // stands for it at the same commit.
        model.fetchCurrentBranch = { _ in "worktree-name" }
        model.stacking.fetch = { _ in
            BranchStack(base: "main", branches: ["lower", "upper"], checkedOut: "upper")
        }
        await model.reload()

        // Listing the checked-out name instead found no pull
        // request for a branch whose pull request was open all along.
        #expect(model.listedBranch == "lower")
        model.show(branch: "upper")
        try? await Task.sleep(for: .milliseconds(200))
        #expect(model.listedBranch == "upper")
        // And the entry in view is what the tab acts on, whatever
        // the worktree happens to hold.
        #expect(model.listedWorktree?.branch == "upper")
    }

    @Test
    func `the stack refuses to push what no push would take`() async {
        let fixtures = PullRequestsModelTests()
        let model = fixtures.makeModel(items: [fixtures.item(branch: "feature", ahead: 1)])
        model.fetchCurrentBranch = { _ in "upper" }
        model.stacking.fetch = { _ in
            BranchStack(base: "main", branches: ["lower", "upper"], checkedOut: "upper")
        }
        model.stacking.unpushed = { _ in ["lower", "upper"] }
        model.stacking.unsigned = { _ in ["lower"] }
        await model.reload()

        // A branch's own Push dims until its tip is signed, since
        // the hook turns unsigned commits away; the stack's did not,
        // and pushed until the first refusal.
        #expect(model.canPushStack == false)
        #expect(model.pushStackHelp.contains("not GPG signed"))

        model.stacking.unsigned = { _ in [] }
        await model.loadStack()

        #expect(model.canPushStack)
    }

    @Test
    func `rebasing one entry carries the branches above it`() async {
        let fixtures = PullRequestsModelTests()
        let model = fixtures.makeModel(items: [fixtures.item(branch: "feature", ahead: 1)])
        model.fetchCurrentBranch = { _ in "upper" }
        model.stacking.fetch = { _ in
            BranchStack(base: "main", branches: ["lower", "upper"], checkedOut: "upper")
        }
        let done = Mutex([String]())
        model.performRebase = { _ in done.withLock { $0.append("rebase") } }
        model.stacking.restack = { _ in
            done.withLock { $0.append("restack") }
            return ["upper"]
        }
        await model.reload()

        #expect(await model.rebaseSigned())

        // Left where they were, the branches above fork from the
        // default branch instead of from the one that moved, and the
        // stack stops being one: the tab then lost the entry that
        // had just moved and showed whatever was checked out.
        #expect(done.withLock { $0 } == ["rebase", "restack"])
    }

    @Test
    func `the listed branch's span is its own, stacked or not`() async {
        let fixtures = PullRequestsModelTests()
        let model = fixtures.makeModel(items: [fixtures.item(branch: "feature", ahead: 1)])
        // On its own: from the default branch to the listed branch,
        // never `HEAD`, which is whatever happens to be checked out.
        model.fetchCurrentBranch = { _ in "feature" }
        await model.reload()
        #expect(model.listedRange == "origin/HEAD..feature")

        model.stacking.fetch = { _ in
            BranchStack(base: "main", branches: ["lower", "upper"], checkedOut: "feature")
        }
        await model.loadStack()
        model.show(branch: "upper")
        try? await Task.sleep(for: .milliseconds(100))
        #expect(model.listedRange == "lower..upper")
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

    /// Puts one branch's listing in the store the model reads, the
    /// way the stack's own prefetch does.
    private func remember(_ model: PullRequestsModel, branch: String, _ summary: PullRequestSummary) {
        model.pullRequests.rememberListing(
            repositoryPath: model.repository.path,
            scope: .branch(branch),
            summaries: [summary],
        )
    }

    private func makeModel() -> PullRequestsModel {
        PullRequestsModelTests().makeModel()
    }
}
