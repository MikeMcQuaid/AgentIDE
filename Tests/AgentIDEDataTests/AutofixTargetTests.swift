@testable import AgentIDEData
import AgentIDEDomain
import Testing

struct AutofixTargetTests {
    @Test(arguments: ["main", "stack-parent", "stack-child"])
    func `only the checked-out non-default stack branch can receive feedback`(branch: String) {
        let repository = Repository(name: "repo", path: "/repo")
        let worktree = Worktree(
            repositoryName: "repo", repositoryPath: "/repo", branch: "stack-child", path: "/worktree",
        )
        let session = AgentSession(
            name: "running", agent: .claudeCode, status: .running, paneID: "pane", activity: .done,
        )
        let item = WorktreeItem(
            worktree: worktree, session: session, isDirty: false, aheadOfUpstream: 0, hasUnread: false,
        )
        let group = RepositoryGroup(repository: repository, items: [item], defaultBranch: "main")
        let summary = PullRequestSummary(
            number: 1, title: "Stack", url: "pr", headBranch: branch, mergeable: "", reviewDecision: "", checks: "",
        )
        let state = PullRequestAutomation(repositoryPath: repository.path, number: 1, url: "pr")
        #expect((SessionService.automationTarget(state, summary: summary, groups: [group]) != nil)
            == (branch == "stack-child"))
        let unknown = RepositoryGroup(repository: repository, items: [item])
        #expect(SessionService.automationTarget(state, summary: summary, groups: [unknown]) == nil)
        let closed = RepositoryGroup(repository: repository, items: [item.withoutSession()], defaultBranch: "main")
        #expect(SessionService.automationTarget(state, summary: summary, groups: [closed]) == nil)
    }
}
