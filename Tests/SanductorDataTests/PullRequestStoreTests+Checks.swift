@testable import SanductorData
import SanductorDomain
import Testing

extension PullRequestStoreTests {
    @Test(arguments: [false, true])
    func `recent summaries refresh missing checks but cache empty checks`(hasDetails: Bool) async throws {
        let file = try TestSupport.temporaryDirectory("pr-check-details") + "/state.json"
        let runner = CountingRunner()
        let store = PullRequestStore(github: GitHubClient(runner: runner), store: MetadataStore(file: file)) { false }
        _ = try await store.summary(repositoryPath: "/repo", number: 7)
        store.rememberSummary(repositoryPath: "/repo", summary: PullRequestSummary(
            number: 7,
            title: "Work",
            url: "https://example.invalid/7",
            headBranch: "work",
            mergeable: "",
            reviewDecision: "",
            checks: "SUCCESS",
            checkDetails: hasDetails ? [] : nil,
        ))
        let before = runner.calls

        let fetched = try await store.summary(repositoryPath: "/repo", number: 7)
        #expect(fetched?.checkDetails != nil)
        #expect(runner.calls == before + (hasDetails ? 0 : 1))
        #expect(fetched?.checkDetails?.isEmpty == hasDetails)
        let cached = try await store.summary(repositoryPath: "/repo", number: 7)
        #expect(cached == fetched)
        #expect(runner.calls == before + (hasDetails ? 0 : 1))
    }
}
