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

    init(checks: String = "SUCCESS") {
        self.checks = checks
    }

    deinit {
        // Nothing to clean up.
    }

    // MARK: Internal

    /// What the one-pull-request answer says its checks are doing.
    var checks: String

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
        // `pr view` answers one object and `pr list` an array; the
        // client wraps a view answer in brackets, so an object serves
        // both here.
        let json = """
        {"number": 7, "title": "Work", "url": "https://example.com/7", "headRefName": "work",
         "baseRefName": "main", "state": "OPEN", "isDraft": false, "author": {"login": "mike"},
         "body": "", "statusCheckRollup": [{"state": "\(checks)"}]}
        """
        let listed = arguments.contains("list") ? "[" + json + "]" : json
        return ProcessResult(status: 0, standardOutput: listed, standardError: "")
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
    func `the branch cache is one structure both the row and the pane read`() throws {
        let file = try TestSupport.temporaryDirectory("pr-branch") + "/state.json"
        let metadata = MetadataStore(file: file)
        let store = PullRequestStore(github: GitHubClient(runner: CountingRunner()), store: metadata)
        let summary = PullRequestSummary(
            number: 7,
            title: "Work",
            url: "https://example.invalid/7",
            headBranch: "work",
            mergeable: "",
            reviewDecision: "",
            checks: "",
            baseBranch: "main",
            state: "OPEN",
        )

        #expect(store.branchSummary(repositoryPath: "/repo", branch: "work") == nil)
        store.rememberBranchSummary(summary, repositoryPath: "/repo", branch: "work")
        #expect(store.branchSummary(repositoryPath: "/repo", branch: "work")?.number == 7)

        // The same field the sidebar's poll has always persisted, so
        // a cache written by an earlier release still paints.
        #expect(metadata.load().pullRequestCache["/repo#work"]?.number == 7)
        store.rememberBranchSummary(nil, repositoryPath: "/repo", branch: "work")
        #expect(store.branchSummary(repositoryPath: "/repo", branch: "work") == nil)
    }

    @Test
    func `a finished turn forgets one branch's stamps and no other's`() async throws {
        let file = try TestSupport.temporaryDirectory("pr-turn") + "/state.json"
        let runner = CountingRunner()
        let store = PullRequestStore(github: GitHubClient(runner: runner), store: MetadataStore(file: file))

        _ = try await store.listing(repositoryPath: "/repo", scope: .branch("work"))
        _ = try await store.listing(repositoryPath: "/repo", scope: .branch("other"))
        #expect(runner.calls == 2)

        // The agent's turn ended, so the branch is assumed to carry
        // fresh commits: its next look asks GitHub now rather than
        // waiting out the interval, and the other branch waits on.
        store.invalidateBranch(repositoryPath: "/repo", branch: "work")
        _ = try await store.listing(repositoryPath: "/repo", scope: .branch("work"))
        _ = try await store.listing(repositoryPath: "/repo", scope: .branch("other"))
        #expect(runner.calls == 3)
    }

    @Test
    func `an entity tag is not sent back once the listing it stamped has gone`() async throws {
        let file = try TestSupport.temporaryDirectory("pr-etag") + "/state.json"
        let runner = CountingRunner()
        let store = PullRequestStore(github: GitHubClient(runner: runner), store: MetadataStore(file: file))
        let key = PullRequestStore.listingKey(repositoryPath: "/repo", scope: .branch("work"))

        // The listing caches are capped and age out; a tag left
        // behind by one asked GitHub for a 304 the app could not
        // answer, so the branch showed no pull request at all for as
        // long as GitHub's own answer stayed the same. A file
        // written that way is answered by asking again in full.
        var orphaned = AppMetadata()
        orphaned.etags[key] = "\"tag-1\""
        try JSONEncoder().encode(orphaned).write(to: URL(fileURLWithPath: file))

        let listed = try await store.listing(repositoryPath: "/repo", scope: .branch("work"))
        #expect(runner.unchangedAnswers == 0)
        #expect(listed.map(\.number) == [7])

        // And a tag is dropped with the listing it belongs to, so
        // the pair can never come apart again.
        let metadata = MetadataStore(file: file)
        var stripped = metadata.load()
        stripped.pullRequestListsCache = [:]
        metadata.update { $0 = stripped }
        #expect(metadata.load().etags.isEmpty)
    }

    @Test
    func `one pull request in flight may be asked about every half minute, a listing may not`() async throws {
        let file = try TestSupport.temporaryDirectory("pr-inflight") + "/state.json"
        let runner = CountingRunner()
        let store = PullRequestStore(github: GitHubClient(runner: runner), store: MetadataStore(file: file))

        // A summary stamped 40 seconds ago is due again at a 30
        // second interval; the listing beside it, stamped the same,
        // is held to the minute floor.
        _ = try await store.summary(repositoryPath: "/repo", number: 7)
        _ = try await store.listing(repositoryPath: "/repo", scope: .branch("work"))
        var metadata = MetadataStore(file: file).load()
        for key in metadata.fetchedAt.keys {
            metadata.fetchedAt[key] = Date().addingTimeInterval(-40)
        }
        MetadataStore(file: file).update { $0 = metadata }
        let before = runner.calls

        _ = try await store.summary(repositoryPath: "/repo", number: 7, interval: 30)
        #expect(runner.calls == before + 1)
        _ = try await store.listing(repositoryPath: "/repo", scope: .branch("work"), interval: 30)
        #expect(runner.calls == before + 1)
    }

    @Test
    func `checks are remembered as pending from when they were first seen running`() async throws {
        let file = try TestSupport.temporaryDirectory("pr-pending") + "/state.json"
        let runner = CountingRunner(checks: "PENDING")
        let store = PullRequestStore(github: GitHubClient(runner: runner), store: MetadataStore(file: file))

        #expect(store.pendingFor(repositoryPath: "/repo", number: 7) == nil)
        _ = try await store.summary(repositoryPath: "/repo", number: 7)
        let pending = try #require(store.pendingFor(repositoryPath: "/repo", number: 7))
        #expect(pending < 5)

        // Finished checks forget the moment, so the next run starts
        // its own clock.
        runner.checks = "SUCCESS"
        store.invalidate(repositoryPath: "/repo", number: 7)
        _ = try await store.summary(repositoryPath: "/repo", number: 7)
        #expect(store.pendingFor(repositoryPath: "/repo", number: 7) == nil)
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
