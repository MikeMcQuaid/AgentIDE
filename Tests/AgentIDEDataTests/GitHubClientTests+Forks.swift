import AgentIDEData
import Foundation
import Testing

extension GitHubClientTests {
    @Test(arguments: [
        "https://github.com/jtbrough/brew.git", "git@github.com:jtbrough/brew.git", "contributor", "origin", "",
    ])
    func `branch listings use the push remote's owner in the upstream repository`(remote: String) async throws {
        let path = try TestSupport.temporaryDirectory("fork-list")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await TestSupport.makeRepository(at: path)
        try await TestSupport.runGit(["remote", "add", "origin", "https://github.com/Homebrew/brew.git"], in: path)
        try await TestSupport.runGit(["remote", "add", "contributor", "https://github.com/jtbrough/brew.git"], in: path)
        try await TestSupport.runGit(["config", "branch.install/check#prefix&mac.remote", "origin"], in: path)
        if remote.isEmpty == false {
            try await TestSupport.runGit(["config", "branch.install/check#prefix&mac.pushremote", remote], in: path)
        }
        let store = PullRequestStore(
            github: GitHubClient(runner: ForkListingRunner(
                owner: remote == "origin" || remote.isEmpty ? "Homebrew" : "jtbrough",
            )),
            store: MetadataStore(file: path + "/state.json"),
        ) { false }

        let listed = try await store.listing(repositoryPath: path, scope: .branch("install/check#prefix&mac"))
        #expect(listed.map(\.number) == [23_959])
        #expect(listed.first?.url == "https://github.com/Homebrew/brew/pull/23959")
        store.invalidateListings(repositoryPath: path)
        let cached = try await store.listing(repositoryPath: path, scope: .branch("install/check#prefix&mac"))
        #expect(cached == listed)
    }
}

// MARK: - ForkListingRunner

private struct ForkListingRunner: ProcessRunner {
    let owner: String

    func run(
        _ arguments: [String],
        workingDirectory: String?,
        environment: [String: String],
    ) async throws -> ProcessResult {
        guard arguments.first == "gh" else {
            return try await FoundationProcessRunner().run(
                arguments,
                workingDirectory: workingDirectory,
                environment: environment,
            )
        }

        #expect(arguments.last == "repos/Homebrew/brew/pulls?state=all&per_page=10&head="
            + owner + "%3Ainstall%2Fcheck%23prefix%26mac")
        if arguments.contains("If-None-Match: \"fork\"") {
            return ProcessResult(status: 1, standardOutput: "HTTP/2.0 304 Not Modified\n\n", standardError: "")
        }
        let body = """
        [{"number": 23959, "title": "Fix", "html_url": "https://github.com/Homebrew/brew/pull/23959",
          "head": {"ref": "install/check#prefix&mac"}, "base": {"ref": "main"}, "state": "open"}]
        """
        return ProcessResult(status: 0, standardOutput: "HTTP/2.0 200 OK\netag: \"fork\"\n\n" + body, standardError: "")
    }
}
