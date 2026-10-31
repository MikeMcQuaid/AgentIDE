@testable import SanductorData
import Testing

// MARK: - PrivateReviewersTests

struct PrivateReviewersTests {
    // Write access, not repository visibility, gates human feedback.
    // swiftlint:disable discouraged_optional_boolean
    @Test(arguments: [true, false, nil] as [Bool?])
    func `verified writers qualify regardless of repository visibility`(isPrivate: Bool?) async throws {
        // swiftlint:enable discouraged_optional_boolean
        let world = try await World.make()
        defer { world.tearDown() }
        let runner = PrivacyRunner(visibility: isPrivate)
        let service = SessionService(
            paths: world.paths,
            git: world.service.git,
            herdr: world.herdr,
            github: GitHubClient(runner: runner) { true },
            transcripts: world.service.transcripts,
            spool: world.service.spool,
            store: world.service.store,
            runners: [],
            processes: runner,
        )
        let state = PullRequestAutomation(repositoryPath: world.repository.path, number: 1, url: AutofixFixture.key)
        for fresh in [false, true] {
            let writers = await service.automationWriters(
                state, authors: ["human"], fresh: fresh,
            )
            #expect(writers == ["human"])
        }
        let permissions = await runner.commands.filter { $0.contains { $0.hasSuffix("/permission") } }
        #expect(permissions.count == 2)
        let visibilityReads = await runner.commands.filter { $0.contains("repos/{owner}/{repo}") }
        #expect(visibilityReads.isEmpty)
    }
}

// MARK: - PrivacyRunner

private actor PrivacyRunner: ProcessRunner {
    // MARK: Lifecycle

    // Unknown visibility is a separate regression case.
    // swiftlint:disable:next discouraged_optional_boolean
    init(visibility: Bool?) {
        self.visibility = visibility
    }

    // MARK: Internal

    var commands: [[String]] = []
    // Nil represents an unavailable visibility response.
    // swiftlint:disable:next discouraged_optional_boolean
    let visibility: Bool?

    func run(
        _ arguments: [String], workingDirectory _: String?, environment _: [String: String], outputLimit _: Int?,
    ) -> ProcessResult {
        commands.append(arguments)
        let privacy = visibility.map { ",\"private\":" + String($0) } ?? ""
        return ProcessResult(status: 0, standardOutput: "{\"permission\":\"write\"" + privacy + "}", standardError: "")
    }
}
