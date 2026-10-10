@testable import AgentIDEData
import AgentIDEDomain
@testable import DashboardFeature
import Testing

extension SessionNavigationTests {
    @Test(arguments: [false, true])
    func `sidebar tracks the worktree's local and PR loops until completion`(local: Bool) throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let model = fixture.model
        let item = try #require(model.groups.first?.items.first)
        let summary = PullRequestSummary(
            number: 7,
            title: "Work",
            url: "https://github.com/upstream/repo/pull/7",
            headBranch: item.worktree.branch,
            mergeable: "",
            reviewDecision: "",
            checks: "",
            state: "OPEN",
        )
        model.branchPullRequests[item.worktree.repositoryPath + "#" + item.worktree.branch] = summary
        let url = local ? "local:" + item.worktree.path : summary.url
        var state = PullRequestAutomation(repositoryPath: item.worktree.repositoryPath, number: 7, url: url)
        let key = PullRequestAutomation.key(for: url)
        #expect(model.feedbackStatus(for: item) == nil)
        state.startLoop()
        model.store.update { $0.pullRequestAutomation[key] = state }
        #expect(model.feedbackStatus(for: item) == state.statusSummary)
        state.isAutomatic = false
        state.loopResult = .finished
        state.pushedCommit = "awaiting-confirmation"
        model.store.update { $0.pullRequestAutomation[key] = state }
        #expect(model.feedbackStatus(for: item) != nil)
        state.pushedCommit = nil
        model.store.update { $0.pullRequestAutomation[key] = state }
        #expect(model.feedbackStatus(for: item) == nil)
        state = PullRequestAutomation(repositoryPath: "/another-checkout", number: 7, url: url)
        state.startLoop()
        model.store.update { $0.pullRequestAutomation[key] = state }
        #expect(model.feedbackStatus(for: item) == nil)
    }
}
