import Foundation
@testable import SanductorData
import SanductorDomain
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

    @Test(arguments: [false, true])
    func `short reads retain cached pages until an authoritative refresh`(explicit: Bool) async throws {
        let root = try TestSupport.temporaryDirectory("pr-list-pages")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let metadata = MetadataStore(file: root + "/state.json")
        let store = PullRequestStore(github: GitHubClient(runner: CountingRunner()), store: metadata) { false }
        let rows = (1 ... 20).map { number in
            PullRequestSummary(
                number: number,
                title: "Old",
                url: "https://example.com/\(number)",
                headBranch: "branch-\(number)",
                mergeable: "",
                reviewDecision: "",
                checks: "",
            )
        }
        store.rememberListing(repositoryPath: "/repo", scope: .open, summaries: rows)
        let key = PullRequestStore.listingKey(repositoryPath: "/repo", scope: .open)
        metadata.update { $0.fetchedAt[key] = Date(timeIntervalSinceNow: -2 * PullRequestStore.minimumInterval) }

        let partial = try await store.listing(repositoryPath: "/repo", scope: .open)
        #expect(partial.count == rows.count)
        #expect(partial.first?.number == 7)
        #expect(partial.first?.title == "Work")
        #expect(store.cachedListing(repositoryPath: "/repo", scope: .open) == partial)

        if explicit {
            store.invalidateListings(repositoryPath: "/repo")
        } else {
            metadata.update { $0.fetchedAt[key] = Date(timeIntervalSinceNow: -2 * PullRequestStore.minimumInterval) }
        }
        let refreshed = try await store.listing(repositoryPath: "/repo", scope: .open, limit: explicit ? 10 : 20)
        #expect(refreshed.map(\.number) == [7])
        #expect(store.cachedListing(repositoryPath: "/repo", scope: .open) == refreshed)
    }
}
