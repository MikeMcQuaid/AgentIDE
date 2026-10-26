import AgentIDEData
import AgentIDEDomain
@testable import PRFeature
import Testing

/// A stack whose lower branch another worktree holds.
extension PullRequestStackTests {
    @Test(arguments: [("lower", false), ("upper", false), ("both", false), ("upper", true), ("both", true)],
          ["idle", "busy", "dirty"])
    func `push readiness considers restack work in selected and published branches`(
        scenario: (String, Bool),
        state: String,
    ) async {
        let (restack, published) = scenario
        let fixtures = PullRequestsModelTests()
        let branch = restack == "lower" ? "lower" : "upper"
        let holder = WorktreeItem(
            worktree: fixtures.item(branch: branch, ahead: 1).worktree,
            session: AgentSession(
                name: branch,
                agent: .claudeCode,
                status: .running,
                activity: state == "busy" ? .working : .idle,
            ),
            isDirty: state == "dirty",
            aheadOfUpstream: 1,
            hasUnread: false,
        )
        let model = fixtures.makeModel(
            items: [fixtures.item(branch: "middle", ahead: 1), holder],
            worktreePath: fixtures.worktreesPath + "/middle",
        )
        model.fetchCurrentBranch = { _ in "middle" }
        model.stacking.facts = { _ in
            StackFacts(
                stack: BranchStack(
                    base: "main",
                    branches: ["lower", "middle", "upper"],
                    checkedOut: "middle",
                    published: published ? ["upper"] : [],
                ),
                outOfPlace: restack == "both" ? ["lower", "upper"] : [restack],
                unpushed: ["middle"],
            )
        }
        await model.reload()
        model.stacking.selected = "middle"

        #expect(model.canRestack == (state == "idle"))
        #expect((model.restackBlocker == nil) == (state == "idle"))
        #expect(model.needsRestackBeforePush == (restack != "upper" || published))
        #expect(model.canPushStack == ((branch == "upper" && published == false) || state == "idle"))
        if branch == "lower" || published, state != "idle" {
            #expect(model.pushStackHelp == model.restackBlocker)
        } else {
            #expect(model.pushStackHelp == "Push the listed branch, those below it "
                + "and published branches above it, bottom first")
        }
    }

    @Test(arguments: [AgentActivity.working, .blocked, .done, .idle])
    func `a branch held by a busy agent dims the restack and the push and names it`(activity: AgentActivity) async {
        let fixtures = PullRequestsModelTests()
        let session = AgentSession(name: "lower", agent: .claudeCode, status: .running, activity: activity)
        let model = fixtures.makeModel(
            items: [
                fixtures.item(branch: "feature", ahead: 1),
                fixtures.item(branch: "lower", ahead: 1, session: session),
            ],
            worktreePath: fixtures.worktreesPath + "/feature",
        )
        model.stacking.facts = { _ in
            StackFacts(
                stack: BranchStack(base: "main", branches: ["lower", "feature"], checkedOut: "feature"),
                outOfPlace: ["lower"],
                unpushed: ["lower", "feature"],
            )
        }
        await model.reload()

        model.stacking.selected = "lower"
        let busy = activity == .working || activity == .blocked
        #expect(model.busyWorktrees == (busy ? [fixtures.worktreesPath + "/lower"] : []))
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
                path: fixtures.worktreesPath + "/lower",
            ),
            session: nil,
            isDirty: true,
            aheadOfUpstream: 1,
            hasUnread: false,
        )
        let model = fixtures.makeModel(
            items: [fixtures.item(branch: "feature", ahead: 1), dirty],
            worktreePath: fixtures.worktreesPath + "/feature",
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
