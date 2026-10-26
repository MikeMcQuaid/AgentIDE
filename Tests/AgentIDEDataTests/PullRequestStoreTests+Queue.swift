@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

extension PullRequestStoreTests {
    @Test(arguments: [
        (#"{"data":{"r0":{"mergeQueue":{"entries":{"nodes":[{"pullRequest":{"number":7}}]}}}}}"#, false),
        ("", true),
        (#"{"data":{"r0":null},"errors":[{"message":"Unavailable"}]}"#, true),
    ])
    func `actions refresh queue membership and failures retain it`(json: String, cached: Bool) async throws {
        let metadata = try MetadataStore(file: TestSupport.temporaryDirectory("queue-store") + "/state.json")
        let store = PullRequestStore(
            github: GitHubClient(runner: QueueRunner(json: json)) { true },
            store: metadata,
        ) { false }
        store.rememberBranchSummary(
            PullRequestSummary(
                number: 7,
                title: "Work",
                url: "",
                headBranch: "work",
                mergeable: "",
                reviewDecision: "",
                checks: "",
                state: "OPEN",
            ),
            repositoryPath: "/repo",
            branch: "work",
        )
        metadata.update { value in
            value.queuedCache["/repo"] = cached ? [7] : []
            value.fetchedAt["queue#/repo"] = Date()
            value.fetchedAt["summary#/repo#7"] = Date()
            value.fetchedAt[PullRequestStore.listingKey(repositoryPath: "/repo", scope: .branch("work"))] = Date()
        }
        #expect(try await store.queuedBranches(repositoryPath: "/repo") == ["work"])
        if cached == false {
            #expect(metadata.load().fetchedAt["summary#/repo#7"] == nil)
            #expect(metadata.load().fetchedAt[
                PullRequestStore.listingKey(repositoryPath: "/repo", scope: .branch("work")),
            ] == nil)
        }
    }

    @Test(arguments: [false, true])
    func `failed queue reads retain queued summary protection`(resolved: Bool) async throws {
        let metadata = try MetadataStore(file: TestSupport.temporaryDirectory("queue-fallback") + "/state.json")
        let store = PullRequestStore(
            github: GitHubClient(runner: QueueRunner(json: "")) { true },
            store: metadata,
        ) { false }
        store.rememberBranchSummary(
            PullRequestSummary(
                number: 7,
                title: "Work",
                url: "",
                headBranch: resolved ? "work" : "",
                mergeable: "",
                reviewDecision: "",
                checks: "",
                isQueued: true,
            ),
            repositoryPath: "/repo",
            branch: "work",
        )
        if resolved {
            #expect(try await store.queuedBranches(repositoryPath: "/repo") == ["work"])
        } else {
            await #expect(throws: SessionServiceError.self) {
                _ = try await store.queuedBranches(repositoryPath: "/repo")
            }
        }
        #expect(metadata.load().queuedCache["/repo"] == nil)
    }

    @Test(arguments: [
        ("", nil as String?),
        ("null", nil),
        ("{}", nil),
        (#"{"number":7,"title":"Work","url":"","headRefName":""}"#, nil),
        (#"{"number":8,"title":"Work","url":"","headRefName":"other"}"#, nil),
        (#"{"number":7,"title":"Work","url":"","headRefName":"work"}"#, "work"),
    ], [false, true])
    func `queued numbers require a matching branch identity`(response: (String, String?), cached: Bool) async throws {
        let metadata = try MetadataStore(file: TestSupport.temporaryDirectory("queue-identity") + "/state.json")
        let runner = QueueRunner(
            json: #"{"data":{"r0":{"mergeQueue":{"entries":{"nodes":[{"pullRequest":{"number":7}}]}}}}}"#,
            summaryJSON: response.0,
        )
        let store = PullRequestStore(github: GitHubClient(runner: runner) { true }, store: metadata) { false }
        if cached {
            let incomplete = PullRequestSummary(
                number: 7,
                title: "Work",
                url: "",
                headBranch: "",
                mergeable: "",
                reviewDecision: "",
                checks: "",
                checkDetails: [],
            )
            store.rememberBranchSummary(incomplete, repositoryPath: "/repo", branch: "work")
            store.rememberSummary(repositoryPath: "/repo", summary: incomplete)
            metadata.update { $0.fetchedAt["summary#/repo#7"] = Date() }
        }

        if let branch = response.1 {
            #expect(try await store.queuedBranches(repositoryPath: "/repo") == [branch])
        } else {
            await #expect(throws: SessionServiceError.self) {
                _ = try await store.queuedBranches(repositoryPath: "/repo")
            }
        }
        #expect(metadata.load().queuedCache["/repo"] == [7])
    }
}

// MARK: - QueueRunner

private struct QueueRunner: ProcessRunner {
    let json: String
    var summaryJSON: String?

    func run(
        _ arguments: [String],
        workingDirectory _: String?,
        environment _: [String: String],
        outputLimit _: Int?,
    ) -> ProcessResult {
        ProcessResult(
            status: 0,
            standardOutput: arguments.first == "git" ? "git@github.com:mike/repo.git\n"
                : (arguments.contains("view") ? summaryJSON ?? json : json),
            standardError: "",
        )
    }
}
