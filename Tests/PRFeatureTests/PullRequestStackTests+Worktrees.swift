import AgentIDEData
import AgentIDEDomain
@testable import PRFeature
import Testing

/// A stack whose lower branch another worktree holds.
extension PullRequestStackTests {
    @Test(arguments: [AgentActivity.working, .blocked, .done, .idle])
    func `a branch held by a busy agent dims the restack and the push and names it`(activity: AgentActivity) async {
        let fixtures = PullRequestsModelTests()
        let session = AgentSession(name: "lower", agent: .claudeCode, status: .running, activity: activity)
        let model = fixtures.makeModel(
            items: [
                fixtures.item(branch: "feature", ahead: 1),
                fixtures.item(branch: "lower", ahead: 1, session: session),
            ],
            worktreePath: "/worktrees/feature",
        )
        model.stacking.facts = { _ in
            StackFacts(
                stack: BranchStack(base: "main", branches: ["lower", "feature"], checkedOut: "feature"),
                outOfPlace: ["lower"],
                unpushed: ["lower", "feature"],
            )
        }
        await model.reload()

        let busy = activity == .working || activity == .blocked
        #expect(model.busyWorktrees == (busy ? ["/worktrees/lower"] : []))
        #expect(model.restackBlocker == (busy ? "`lower`'s agent is busy; rebase once it is idle or done" : nil))
        #expect(model.canRestack == !busy)
        #expect(model.canPushStack == !busy)
        if busy {
            #expect(model.pushStackHelp == model.restackBlocker)
        }
    }

    @Test
    func `a branch held by a dirty worktree dims the restack`() async {
        let fixtures = PullRequestsModelTests()
        let dirty = WorktreeItem(
            worktree: Worktree(
                repositoryName: "repo",
                repositoryPath: "/repo",
                branch: "lower",
                path: "/worktrees/lower",
            ),
            session: nil,
            isDirty: true,
            aheadOfUpstream: 1,
            hasUnread: false,
        )
        let model = fixtures.makeModel(
            items: [fixtures.item(branch: "feature", ahead: 1), dirty],
            worktreePath: "/worktrees/feature",
        )
        model.stacking.facts = { _ in
            StackFacts(
                stack: BranchStack(base: "main", branches: ["lower", "feature"], checkedOut: "feature"),
                outOfPlace: ["lower"],
            )
        }
        await model.reload()

        #expect(model.restackBlocker == "Commit or discard the changes in `lower`'s worktree first")
        #expect(model.canRestack == false)
    }
}
