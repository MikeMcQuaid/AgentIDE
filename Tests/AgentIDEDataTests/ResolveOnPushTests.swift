@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

// MARK: - ResolveOnPushTests

struct ResolveOnPushTests {
    @Test
    func `marking and cancelling a loaded thread never contact GitHub`() throws {
        let root = try TestSupport.temporaryDirectory("local-resolution")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let store = MetadataStore(file: root + "/state.json")
        let requests = PullRequestStore(github: GitHubClient(runner: NoResolutionNetwork()) { true }, store: store)
        let summary = PullRequestSummary(
            number: 7,
            title: "Work",
            url: "https://github.com/o/r/pull/7",
            headBranch: "feature",
            mergeable: "",
            reviewDecision: "",
            checks: "",
            headCommit: "reviewed-head",
        )
        requests.rememberSummary(repositoryPath: "/repo", summary: summary)
        let thread = ReviewThread(
            id: "thread",
            path: "file.swift",
            line: 1,
            isResolved: false,
            comments: [ReviewThreadComment(author: "reviewer", body: "Fix this", id: "comment")],
        )
        try requests.toggleResolveOnPush(repositoryPath: "/repo", summary: summary, thread: thread)
        let key = PullRequestAutomation.key(for: summary.url)
        #expect(store.load().pullRequestAutomation[key]?.resolutions["thread"] == PendingThreadResolution(
            head: "reviewed-head", commentID: "comment",
        ))
        try requests.toggleResolveOnPush(repositoryPath: "/repo", summary: summary, thread: thread)
        #expect(store.load().pullRequestAutomation[key]?.resolutions.isEmpty == true)
    }
}

// MARK: - NoResolutionNetwork

private struct NoResolutionNetwork: ProcessRunner {
    func run(
        _ arguments: [String], workingDirectory _: String?, environment _: [String: String], outputLimit _: Int?,
    ) -> ProcessResult {
        Issue.record("A local review action spawned \(arguments.joined(separator: " "))")
        return ProcessResult(status: 1, standardOutput: "", standardError: "Offline")
    }
}
