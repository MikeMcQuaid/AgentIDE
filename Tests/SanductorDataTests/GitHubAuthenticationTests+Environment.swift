import Foundation
@testable import SanductorData
import Testing

extension GitHubAuthenticationTests {
    @Test(arguments: [true, false])
    func `rejected overrides are removed application wide before credential recovery`(storedLoginWorks: Bool) async {
        // Changing the real process environment must not affect parallel tests.
        await #expect(processExitsWith: .success) { [storedLoginWorks] in
            unsafe setenv("GH_TOKEN", "expired", 1)
            unsafe setenv("GITHUB_TOKEN", "expired", 1)
            unsafe setenv("SANDUCTOR_AUTH_ENV_TEST", "kept", 1)
            let runner = TokenOverrideRunner(storedLoginWorks: storedLoginWorks)
            let github = GitHubClient(runner: runner) { true }
            let result = try? await github.gh(["api", "user"], in: "/one")
            try #require(ProcessInfo.processInfo.environment["GH_TOKEN"] == nil)
            try #require(ProcessInfo.processInfo.environment["GITHUB_TOKEN"] == nil)
            try #require((result?.succeeded == true) == storedLoginWorks)
            if storedLoginWorks {
                let other = try await GitHubClient(runner: runner) { true }.gh(["api", "user"], in: "/two")
                try #require(other.succeeded)
                try #require(await runner.commands == [
                    ["gh", "api", "user"], ["gh", "auth", "status", "--active", "--hostname", "github.com"],
                    ["gh", "api", "user"], ["gh", "api", "user"],
                ])
            } else {
                _ = try? await github.gh(["api", "user"], in: "/two")
                try #require(await runner.commands.count == 2)
                try #require(GitHubAuthenticationError().localizedDescription.contains("unset") == false)
            }
            let inherited = try await FoundationProcessRunner().run(
                [
                    "/bin/sh", "-c", #"test -z "${GH_TOKEN+x}" && test -z "${GITHUB_TOKEN+x}" "#
                        + #"&& test "$SANDUCTOR_AUTH_ENV_TEST" = kept"#,
                ],
                workingDirectory: nil,
                environment: [:],
            )
            try #require(inherited.succeeded)
        }
    }

    @Test
    func `working token overrides are retained until a rejection`() async {
        await #expect(processExitsWith: .success) {
            unsafe setenv("GH_TOKEN", "valid", 1)
            unsafe setenv("GITHUB_TOKEN", "valid", 1)
            let runner = TokenOverrideRunner(storedLoginWorks: true)
            let github = GitHubClient(runner: runner) { true }
            let result = try await github.gh(["api", "user"], in: "/repo")
            try #require(result.succeeded)
            try #require(ProcessEnvironment.scrubbed()["GH_TOKEN"] == "valid")
            try #require(ProcessEnvironment.scrubbed()["GITHUB_TOKEN"] == "valid")
            try #require(await runner.commands == [["gh", "api", "user"]])
        }
    }
}

// MARK: - TokenOverrideRunner

private actor TokenOverrideRunner: ProcessRunner {
    // MARK: Lifecycle

    init(storedLoginWorks: Bool) {
        self.storedLoginWorks = storedLoginWorks
    }

    // MARK: Internal

    var commands: [[String]] = []

    func run(
        _ arguments: [String], workingDirectory _: String?, environment: [String: String], outputLimit _: Int?,
    ) -> ProcessResult {
        commands.append(arguments)
        let inherited = ProcessEnvironment.scrubbed(merging: environment)
        let accepted = storedLoginWorks && inherited["GH_TOKEN"] != "expired" && inherited["GITHUB_TOKEN"] != "expired"
        return ProcessResult(
            status: accepted ? 0 : 1,
            standardOutput: accepted ? "{}" : "",
            standardError: accepted ? "" : "gh: Bad credentials (HTTP 401)",
        )
    }

    // MARK: Private

    private let storedLoginWorks: Bool
}
