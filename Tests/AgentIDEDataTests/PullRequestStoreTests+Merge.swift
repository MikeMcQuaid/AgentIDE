@testable import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

extension PullRequestStoreTests {
    @Test
    func `a requested merge refreshes its branch and queue and survives a relaunch`() throws {
        let file = try TestSupport.temporaryDirectory("pr-merge-request") + "/state.json"
        let metadata = MetadataStore(file: file)
        let github = GitHubClient(runner: RecordingRunner())
        let store = PullRequestStore(github: github, store: metadata)
        let listing = PullRequestStore.listingKey(repositoryPath: "/repo", scope: .branch("work"))
        let other = PullRequestStore.listingKey(repositoryPath: "/repo", scope: .branch("other"))
        metadata.update { $0.fetchedAt = [listing: Date(), other: Date(), "queue#/repo": Date()] }

        store.markMergeRequested(repositoryPath: "/repo", branches: ["work"])

        #expect(metadata.load().fetchedAt[listing] == nil)
        #expect(metadata.load().fetchedAt["queue#/repo"] == nil)
        #expect(metadata.load().fetchedAt[other] != nil)
        let relaunched = PullRequestStore(github: github, store: MetadataStore(file: file))
        #expect(relaunched.mergeRequestedRecently(repositoryPath: "/repo", branch: "work"))
        #expect(relaunched.mergeRequestedRecently(repositoryPath: "/repo", branch: "other") == false)

        metadata.update { state in
            state.fetchedAt[PullRequestStore.mergeRequestKey(repositoryPath: "/repo", branch: "work")] =
                Date().addingTimeInterval(-RefreshCadence.mergeRequestPatience)
        }
        #expect(relaunched.mergeRequestedRecently(repositoryPath: "/repo", branch: "work") == false)
    }

    @Test(arguments: ["OPEN", "MERGED", "CLOSED"])
    func `a requested merge stops speeding up the poll once the branch finishes`(state: String) throws {
        let file = try TestSupport.temporaryDirectory("pr-merge-finished") + "/state.json"
        let store = PullRequestStore(github: GitHubClient(runner: RecordingRunner()), store: MetadataStore(file: file))
        store.markMergeRequested(repositoryPath: "/repo", branches: ["work"])
        store.rememberBranchSummary(
            PullRequestSummary(
                number: 7,
                title: "Work",
                url: "",
                headBranch: "work",
                mergeable: "",
                reviewDecision: "",
                checks: "",
                state: state,
            ),
            repositoryPath: "/repo",
            branch: "work",
        )
        #expect(store.mergeRequestedRecently(repositoryPath: "/repo", branch: "work") == (state == "OPEN"))
    }
}
