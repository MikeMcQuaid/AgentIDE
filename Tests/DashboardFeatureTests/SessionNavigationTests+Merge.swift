@testable import AgentIDEData
import AgentIDEDomain
@testable import DashboardFeature
import Foundation
import Testing

extension SessionNavigationTests {
    @Test(arguments: ["idle", "requested", "queued", "expired"])
    func `the usual poll speeds up for requested and queued merges`(state: String) async {
        let fixture = Fixture(runner: MergePollRunner(queued: state == "queued"))
        defer { fixture.close() }
        let model = fixture.model
        let repository = fixture.repository
        model.groups[0] = RepositoryGroup(repository: repository, items: model.groups[0].items, defaultBranch: "other")
        model.branchPullRequests[repository.path + "#main"] = PullRequestSummary(
            number: 7,
            title: "Work",
            url: "",
            headBranch: "main",
            mergeable: "MERGEABLE",
            reviewDecision: "APPROVED",
            checks: "SUCCESS",
            state: "OPEN",
        )
        if state == "requested" || state == "expired" {
            model.pullRequests.markMergeRequested(repositoryPath: repository.path, branches: ["main"])
        }
        model.queuedNumbers[repository.path] = state == "queued" ? [7] : []
        let listing = PullRequestStore.listingKey(repositoryPath: repository.path, scope: .branch("main"))
        let queue = "queue#" + repository.path
        let before = Date().addingTimeInterval(-RefreshCadence.slowed(90, onBattery: PowerSource.isOnBattery))
        model.store.update { metadata in
            metadata.fetchedAt[listing] = before
            metadata.fetchedAt[queue] = before
            metadata.queuedCache[repository.path] = state == "queued" ? [7] : []
            if state == "expired" {
                metadata.fetchedAt[PullRequestStore.mergeRequestKey(repositoryPath: repository.path, branch: "main")] =
                    Date().addingTimeInterval(-RefreshCadence.mergeRequestPatience)
            }
        }

        await model.refreshStalePullRequests(forcing: [])

        let faster = state == "requested" || state == "queued"
        #expect((model.store.load().fetchedAt[listing] != before) == faster)
        #expect((model.store.load().fetchedAt[queue] != before) == faster)
    }
}

// MARK: - MergePollRunner

private struct MergePollRunner: ProcessRunner {
    let queued: Bool

    @concurrent
    func run(
        _ arguments: [String],
        workingDirectory _: String?,
        environment _: [String: String],
        outputLimit _: Int?,
    ) async -> ProcessResult {
        let output: String
        if arguments.first == "git" {
            output = "git@github.com:owner/repo.git"
        } else if arguments.contains("graphql") {
            let nodes = queued ? #"{"pullRequest":{"number":7}}"# : ""
            output = #"{"data":{"r0":{"mergeQueue":{"entries":{"nodes":[\#(nodes)]}}}}}"#
        } else {
            output = "HTTP/2.0 200 OK\r\n\r\n[]"
        }
        return ProcessResult(status: 0, standardOutput: output, standardError: "")
    }
}
