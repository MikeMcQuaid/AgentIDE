@testable import AgentIDEData
import Testing

/// The pull request tab's pager asking past the listing it holds.
extension PullRequestStoreTests {
    @Test
    func `a page further than the cache holds is asked at once`() async throws {
        let file = try TestSupport.temporaryDirectory("pr-further") + "/state.json"
        let runner = CountingRunner()
        let store = PullRequestStore(github: GitHubClient(runner: runner), store: MetadataStore(file: file)) { false }

        _ = try await store.listing(repositoryPath: "/repo", scope: .open)
        _ = try await store.listing(repositoryPath: "/repo", scope: .open, limit: 2 * GitHubClient.listLimit)
        #expect(runner.calls == 2)

        // The usual ask is still held to the floor.
        _ = try await store.listing(repositoryPath: "/repo", scope: .open)
        #expect(runner.calls == 2)
    }
}
