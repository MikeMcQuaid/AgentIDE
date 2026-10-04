import AgentIDEData
import AgentIDEDomain
import Foundation
@testable import PRFeature
import Synchronization
import Testing

extension PullRequestsModelTests {
    @Test(arguments: [
        ("plain", "repos/{owner}/{repo}/pulls/7/merge"),
        ("queue", "repos/{owner}/{repo}/pulls/7/merge-async"),
        ("queue-pending", "--auto"),
        ("queue-review", "--auto"),
        ("queue-unknown", "--auto"),
        ("queue-draft", "ready"),
        ("queue-cancel", "--disable-auto"),
        ("queue-queued", "id=PR_7"),
        ("draft", "ready"),
        ("automerge", "--auto"),
        ("cancel", "--disable-auto"),
    ])
    func `merge actions choose the appropriate API`(state: String, command: String) async throws {
        let root = FileManager.default.currentDirectoryPath + "/.test-scratch/merge-routing-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: root) }
        let store = MetadataStore(file: root + "/state.json")
        store.update { metadata in
            metadata.mergeQueueCapability["/repo"] = state.hasPrefix("queue")
            metadata.fetchedAt["queue-capability#/repo"] = Date()
        }
        let runner = MergeRoutingRunner()
        let github = GitHubClient(runner: runner) { true }
        let summary = PullRequestSummary(
            number: 7,
            title: "Work",
            url: "",
            headBranch: "feature",
            mergeable: state == "queue-unknown" ? "UNKNOWN" : "MERGEABLE",
            reviewDecision: state == "queue-review" ? "REVIEW_REQUIRED" : "APPROVED",
            checks: ["automerge", "queue-pending"].contains(state) ? "PENDING" : "SUCCESS",
            isDraft: state.hasSuffix("draft"),
            hasAutomerge: state.hasSuffix("cancel") || state == "queue-queued",
            isQueued: state == "queue-queued",
        )
        _ = try await PullRequestsModel.mergeChange(
            summary,
            github: github,
            repository: Repository(name: "repo", path: "/repo"),
            gate: PullRequestStore(github: github, store: store),
        )
        let calls = runner.calls.withLock { $0 }
        #expect(calls.count == 1)
        #expect(calls.first?.contains(command) == true)
        if state.hasPrefix("queue"), command == "--auto" {
            #expect(calls.first == ["gh", "pr", "merge", "7", "--auto"])
        }
        if state == "queue-queued" {
            #expect(calls.first?.contains(
                "query=mutation($id: ID!) { dequeuePullRequest(input: { id: $id }) { clientMutationId } }",
            ) == true)
        }
    }
}

// MARK: - MergeRoutingRunner

private final nonisolated class MergeRoutingRunner: ProcessRunner {
    // MARK: Lifecycle

    deinit {
        // No resources to release.
    }

    // MARK: Internal

    let calls: Mutex = .init([[String]]())

    func run(
        _ arguments: [String],
        workingDirectory _: String?,
        environment _: [String: String],
        outputLimit _: Int?,
    ) -> ProcessResult {
        if arguments.starts(with: ["gh", "repo", "view"]) {
            return ProcessResult(status: 0, standardOutput: #"{"mergeCommitAllowed":true}"#, standardError: "")
        }
        if arguments == ["gh", "pr", "view", "7", "--json", "id", "--jq", ".id"] {
            return ProcessResult(status: 0, standardOutput: "PR_7\n", standardError: "")
        }
        calls.withLock { $0.append(arguments) }
        let body = arguments.contains("repos/{owner}/{repo}/pulls/7/merge-async")
            ? #"{"status":"pending","details":{}}"# : #"{"merged":true}"#
        return ProcessResult(status: 0, standardOutput: "HTTP/2.0 200 OK\r\n\r\n" + body, standardError: "")
    }
}
