@testable import SanductorData
import Testing

// MARK: - GitHubAuthenticationTests

struct GitHubAuthenticationTests {
    @Test
    func `a rejected sign-in stops requests across repositories including allowed failures`() async {
        let runner = AuthenticationRunner(recovers: false)
        let github = GitHubClient(runner: runner) { true }
        for path in ["/one", "/two", "/three"] {
            _ = try? await github.gh(["api", "user"], in: path, allowFailure: true)
        }
        #expect(await runner.commands == [
            ["gh", "api", "user"], ["gh", "auth", "status", "--active", "--hostname", "github.com"],
        ])
    }

    @Test
    func `an expired credential recovers once and retries a read`() async {
        let runner = AuthenticationRunner(recovers: true)
        let github = GitHubClient(runner: runner) { true }
        let answer = try? await github.gh(["api", "user"], in: "/repo")
        #expect(answer?.succeeded == true)
        #expect(await runner.commands == [
            ["gh", "api", "user"], ["gh", "auth", "status", "--active", "--hostname", "github.com"],
            ["gh", "api", "user"],
        ])
    }

    @Test
    func `recovering authentication never replays a mutation`() async {
        let runner = AuthenticationRunner(recovers: true)
        let github = GitHubClient(runner: runner) { true }
        let command = ["api", "graphql", "-f", "query=mutation { changeSomething }"]
        await #expect(throws: (any Error).self) {
            try await github.gh(command, in: "/repo")
        }
        #expect(await runner.commands == [
            ["gh"] + command, ["gh", "auth", "status", "--active", "--hostname", "github.com"],
        ])
    }

    @Test
    func `a merge rejected for authentication cannot fall through to an async merge`() async {
        let runner = AuthenticationRunner(recovers: true)
        let github = GitHubClient(runner: runner) { true }
        await #expect(throws: (any Error).self) {
            try await github.merge(repositoryPath: "/repo", number: 7, usingMergeQueue: true)
        }
        #expect(await runner.commands == [
            ["gh", "pr", "merge", "7"], ["gh", "auth", "status", "--active", "--hostname", "github.com"],
        ])
    }
}

// MARK: - AuthenticationRunner

private actor AuthenticationRunner: ProcessRunner {
    // MARK: Lifecycle

    init(recovers: Bool) {
        self.recovers = recovers
    }

    // MARK: Internal

    var commands: [[String]] = []

    func run(
        _ arguments: [String], workingDirectory _: String?, environment _: [String: String], outputLimit _: Int?,
    ) -> ProcessResult {
        commands.append(arguments)
        if arguments.starts(with: ["gh", "auth", "status"]) {
            authenticated = recovers
        }
        return ProcessResult(
            status: authenticated ? 0 : 1,
            standardOutput: authenticated ? "{}" : "",
            standardError: authenticated ? "" : "gh: Bad credentials (HTTP 401)",
        )
    }

    // MARK: Private

    private let recovers: Bool
    private var authenticated = false
}
