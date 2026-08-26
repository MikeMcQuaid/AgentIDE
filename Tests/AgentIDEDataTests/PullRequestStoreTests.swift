@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

// MARK: - CountingRunner

/// A `gh` and `git` that answer a branch's listing, counting how
/// often GitHub was asked, and answering a repeated question with
/// 304 the way GitHub does when the entity tag still matches.
private final class CountingRunner: ProcessRunner, @unchecked Sendable {
    // MARK: Lifecycle

    deinit {
        // Nothing to clean up.
    }

    // MARK: Internal

    // periphery:ignore - read by the tests below.
    private(set) var calls = 0

    // periphery:ignore - read by the tests below.
    private(set) var unchangedAnswers = 0

    func run(
        _ arguments: [String],
        workingDirectory _: String?,
        environment _: [String: String],
    ) -> ProcessResult {
        if arguments.first == "git" || arguments.contains("remote") {
            return ProcessResult(status: 0, standardOutput: "git@github.com:mike/repo.git\n", standardError: "")
        }

        calls += 1
        if arguments.contains("--include") {
            if arguments.contains(where: { $0.hasPrefix("If-None-Match:") }) {
                unchangedAnswers += 1
                return ProcessResult(
                    status: 1,
                    standardOutput: "HTTP/2.0 304 Not Modified\netag: \"tag-1\"\n\n",
                    standardError: "",
                )
            }
            let body = """
            [{"number": 7, "title": "Work", "html_url": "https://example.com/7", "head": {"ref": "work"},
              "base": {"ref": "main"}, "state": "open", "draft": false, "user": {"login": "mike"}, "body": ""}]
            """
            return ProcessResult(
                status: 0,
                standardOutput: "HTTP/2.0 200 OK\netag: \"tag-1\"\n\n" + body,
                standardError: "",
            )
        }
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

        // Acting on the branch, rather than looking at it, asks again;
        // the entity tag goes with the question, GitHub says nothing
        // changed, and the cache answers without a byte of listing.
        relaunched.invalidateListings(repositoryPath: "/repo")
        let again = try await relaunched.listing(repositoryPath: "/repo", scope: .branch("work"))
        #expect(runner.calls == 2)
        #expect(runner.unchangedAnswers == 1)
        #expect(again.map(\.number) == [7])
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
