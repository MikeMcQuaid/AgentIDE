@testable import SanductorData
import Testing

// MARK: - GitCredentialEnvironmentTests

struct GitCredentialEnvironmentTests {
    @Test(arguments: ["fetch", "push", "pull", "clone", "ls-remote", "status"])
    func `remote git commands ignore inherited token overrides`(_ command: String) async throws {
        let result = try await GitClient(runner: CredentialEnvironmentRunner()) { true }.git(
            [command], in: nil, environment: ["GIT_INDEX_FILE": "kept"],
        )
        #expect(result.standardOutput == (command == "status" ? "expired:expired:kept" : "stored:stored:kept"))
    }
}

// MARK: - CredentialEnvironmentRunner

private struct CredentialEnvironmentRunner: ProcessRunner {
    func run(
        _: [String], workingDirectory _: String?, environment: [String: String], outputLimit _: Int?,
    ) async throws -> ProcessResult {
        try await FoundationProcessRunner().run(
            ["/bin/sh", "-c", #"printf '%s:%s:%s' "${GH_TOKEN:-stored}" "${GITHUB_TOKEN:-stored}" "$GIT_INDEX_FILE""#],
            workingDirectory: nil,
            environment: ["GH_TOKEN": "expired", "GITHUB_TOKEN": "expired"].merging(environment) { _, new in new },
        )
    }
}
