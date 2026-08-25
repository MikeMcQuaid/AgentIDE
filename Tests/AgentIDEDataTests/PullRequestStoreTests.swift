@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

// MARK: - CountingRunner

/// A `gh` that answers the same listing every time and counts how
/// often it was asked.
private final class CountingRunner: ProcessRunner, @unchecked Sendable {
    // MARK: Lifecycle

    deinit {
        // Nothing to clean up.
    }

    // MARK: Internal

    // periphery:ignore - read by the tests below.
    private(set) var calls = 0

    func run(
        _: [String],
        workingDirectory _: String?,
        environment _: [String: String],
    ) -> ProcessResult {
        calls += 1
        let json = """
        [{"number": 7, "title": "Work", "url": "https://example.com/7", "headRefName": "work",
          "baseRefName": "main", "state": "OPEN", "isDraft": false, "author": {"login": "mike"},
          "body": ""}]
        """
        return ProcessResult(status: 0, standardOutput: json, standardError: "")
    }
}

// MARK: - PullRequestStoreTests

/// The one gate every pull request question goes through: asked
/// twice in a minute, GitHub hears it once, and the timer outlives
/// the app rather than the view that happened to ask.
struct PullRequestStoreTests {
    @Test
    func `a pull request is asked about once a minute however often it is looked at`() async throws {
        let file = try TestSupport.temporaryDirectory("pr-store") + "/state.json"
        let runner = CountingRunner()
        let store = PullRequestStore(github: GitHubClient(runner: runner), store: MetadataStore(file: file))

        let first = try await store.listing(repositoryPath: "/repo", scope: .branch("work"))
        for _ in 0 ..< 5 {
            _ = try await store.listing(repositoryPath: "/repo", scope: .branch("work"))
        }

        #expect(first.map(\.number) == [7])
        #expect(runner.calls == 1)

        // A fresh store over the same file is what a relaunch is.
        let relaunched = PullRequestStore(
            github: GitHubClient(runner: runner),
            store: MetadataStore(file: file),
        )
        let afterRelaunch = try await relaunched.listing(repositoryPath: "/repo", scope: .branch("work"))
        #expect(afterRelaunch.map(\.number) == [7])
        #expect(runner.calls == 1)

        // The sidebar's poll is told nothing is due rather than
        // being handed the cache it already has.
        let due = try await relaunched.listingIfDue(repositoryPath: "/repo", scope: .branch("work"))
        #expect(due == nil)

        // Acting on the branch, rather than looking at it, asks again.
        relaunched.invalidateListings(repositoryPath: "/repo")
        _ = try await relaunched.listing(repositoryPath: "/repo", scope: .branch("work"))
        #expect(runner.calls == 2)
    }

    @Test
    func `a caller cannot ask for a shorter interval than the floor`() async throws {
        let file = try TestSupport.temporaryDirectory("pr-floor") + "/state.json"
        let runner = CountingRunner()
        let store = PullRequestStore(github: GitHubClient(runner: runner), store: MetadataStore(file: file))

        _ = try await store.listing(repositoryPath: "/repo", scope: .open, interval: 0)
        _ = try await store.listing(repositoryPath: "/repo", scope: .open, interval: 0)

        #expect(runner.calls == 1)
    }
}
