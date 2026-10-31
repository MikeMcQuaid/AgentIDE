import AppKit
@testable import DashboardFeature
import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

extension SessionNavigationTests {
    @Test
    func `manual repository refresh reloads its required jobs`() async {
        _ = NSApplication.shared
        let fixture = Fixture()
        defer { fixture.close() }
        let model = fixture.model
        let path = fixture.repository.path
        model.store.update { metadata in
            for repository in [path, path + "-other"] {
                let key = PullRequestStore.requiredChecksKey(repositoryPath: repository, branch: "main")
                metadata.requiredChecksCache[key] = ["old-job"]
                metadata.fetchedAt[key] = Date()
            }
        }
        #expect(await model.pullRequests.requiredChecks(repositoryPath: path, branch: "main") == ["old-job"])

        await model.refreshRepository(path: path)

        #expect(await model.pullRequests.requiredChecks(repositoryPath: path, branch: "main")?.isEmpty == true)
        #expect(await model.pullRequests.requiredChecks(repositoryPath: path + "-other", branch: "main") == ["old-job"])
    }

    @Test
    func `the sidebar follows a replacement PR and queue changes from the shared store`() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let model = fixture.model
        let item = try #require(model.groups.first?.items.first)
        let old = PullRequestSummary(
            number: 7,
            title: "Old",
            url: "",
            headBranch: "main",
            mergeable: "",
            reviewDecision: "",
            checks: "",
            state: "OPEN",
        )
        model.pullRequests.rememberBranchSummary(old, repositoryPath: fixture.repository.path, branch: "main")
        await model.refreshStalePullRequests(forcing: [])
        let fresh = PullRequestSummary(
            number: 8,
            title: "New",
            url: "",
            headBranch: "main",
            mergeable: "",
            reviewDecision: "",
            checks: "",
            state: "OPEN",
        )
        model.pullRequests.rememberBranchSummary(fresh, repositoryPath: fixture.repository.path, branch: "main")
        model.store.update { $0.queuedCache[fixture.repository.path] = [8] }

        #expect(model.pullRequest(for: item)?.number == 8)
        #expect(model.pullRequest(for: item)?.isQueued == true)
    }

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
        model.pullRequests.rememberBranchSummary(
            summary, repositoryPath: item.worktree.repositoryPath, branch: item.worktree.branch,
        )
        let url = local ? "local:" + item.worktree.path : summary.url
        var state = PullRequestAutomation(repositoryPath: item.worktree.repositoryPath, number: 7, url: url)
        let key = PullRequestAutomation.key(for: url)
        #expect(model.feedbackStatus(for: item) == nil)
        state.startLoop()
        model.store.update { $0.pullRequestAutomation[key] = state }
        #expect(model.feedbackStatus(for: item) == state.statusSummary)
        state.isAutomatic = false
        state.loopResult = .finished
        model.store.update { $0.pullRequestAutomation[key] = state }
        #expect(model.feedbackStatus(for: item) == nil)
        state = PullRequestAutomation(repositoryPath: "/another-checkout", number: 7, url: url)
        state.startLoop()
        model.store.update { $0.pullRequestAutomation[key] = state }
        #expect(model.feedbackStatus(for: item) == nil)
    }
}
