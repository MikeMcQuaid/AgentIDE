import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

/// What a push paints into the caches before GitHub has seen it.
extension PullRequestStoreTests {
    @Test
    func `a push paints its pull request pending in every cache`() throws {
        let file = try TestSupport.temporaryDirectory("pr-store-pending") + "/state.json"
        let store = PullRequestStore(
            github: GitHubClient(runner: FoundationProcessRunner()),
            store: MetadataStore(file: file),
        ) { false }
        let green = Self.greenAtOldHead
        let other = PullRequestSummary(
            number: 8,
            title: "Elsewhere",
            url: "",
            headBranch: "other",
            mergeable: "MERGEABLE",
            reviewDecision: "",
            checks: "SUCCESS",
            baseBranch: "main",
        )
        store.rememberBranchSummary(green, repositoryPath: "/repo", branch: "feature")
        store.rememberListing(repositoryPath: "/repo", scope: .branch("feature"), summaries: [green])
        store.rememberListing(repositoryPath: "/repo", scope: .open, summaries: [green, other])
        store.rememberSummary(repositoryPath: "/repo", summary: green)

        store.markChecksPending(repositoryPath: "/repo", branches: ["feature"])

        // The row, the tab's listing and the pane's header all say
        // pending, and a pull request nothing pushed is left alone.
        #expect(store.branchSummary(repositoryPath: "/repo", branch: "feature")?.checks == "PENDING")
        #expect(store.cachedListing(repositoryPath: "/repo", scope: .branch("feature"))?.first?.checks == "PENDING")
        let listed = store.cachedListing(repositoryPath: "/repo", scope: .open) ?? []
        #expect(listed.map(\.checks) == ["PENDING", "SUCCESS"])
        #expect(store.cachedSummary(repositoryPath: "/repo", number: 7)?.checks == "PENDING")
    }

    @Test
    func `the paint outlives a fetch GitHub answers before it has seen the push`() throws {
        let file = try TestSupport.temporaryDirectory("pr-store-stale") + "/state.json"
        let store = PullRequestStore(
            github: GitHubClient(runner: FoundationProcessRunner()),
            store: MetadataStore(file: file),
        ) { false }
        let green = Self.greenAtOldHead
        store.rememberBranchSummary(green, repositoryPath: "/repo", branch: "feature")
        store.markChecksPending(repositoryPath: "/repo", branches: ["feature"])

        // GitHub has not seen the push: it still reports the head it
        // reported before, with the old run's verdict, and that is
        // painted pending as it arrives.
        let stale = store.rememberListing(repositoryPath: "/repo", scope: .branch("feature"), summaries: [green])
        #expect(stale.first?.checks == "PENDING")
        store.rememberBranchSummary(green, repositoryPath: "/repo", branch: "feature")
        #expect(store.branchSummary(repositoryPath: "/repo", branch: "feature")?.checks == "PENDING")

        // GitHub has caught up: another head, and its rollup is about
        // the new commits, whatever it says.
        let caughtUp = PullRequestSummary(
            number: 7,
            title: "Work",
            url: "",
            headBranch: "feature",
            mergeable: "MERGEABLE",
            reviewDecision: "APPROVED",
            checks: "SUCCESS",
            baseBranch: "main",
            headCommit: "new",
        )
        let fresh = store.rememberListing(repositoryPath: "/repo", scope: .branch("feature"), summaries: [caughtUp])
        #expect(fresh.first?.checks == "SUCCESS")
        // And the mark is gone: the next stale-looking answer is real.
        store.rememberBranchSummary(green, repositoryPath: "/repo", branch: "feature")
        #expect(store.branchSummary(repositoryPath: "/repo", branch: "feature")?.checks == "SUCCESS")
    }

    /// The pull request every case here is about.
    private static let number = 7

    /// A green pull request GitHub last reported at the head `old`.
    private static let greenAtOldHead: PullRequestSummary = .init(
        number: number,
        title: "Work",
        url: "",
        headBranch: "feature",
        mergeable: "MERGEABLE",
        reviewDecision: "APPROVED",
        checks: "SUCCESS",
        baseBranch: "main",
        headCommit: "old",
    )
}
