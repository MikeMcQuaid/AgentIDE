import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

// MARK: - CloneRepositoryTests

/// Opening a repository from the finder: a checkout is matched by
/// its GitHub `owner/name`, never by the bare name another owner's
/// clone may share.
struct CloneRepositoryTests {
    @Test
    func `a repository sharing a cloned name clones beside it under its owner`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let github = RecordingRunner()
        let service = SessionService(
            paths: world.paths,
            git: GitClient(runner: FoundationProcessRunner()),
            herdr: world.herdr,
            github: GitHubClient(runner: github) { true },
            transcripts: TranscriptReader(),
            spool: EventSpool(directory: world.paths.eventsDirectory),
            store: MetadataStore(file: world.paths.metadataFile),
            runners: [],
        )
        let forkPath = world.paths.repositoriesDirectory + "/Example"
        try await TestSupport.makeRepository(at: forkPath)
        try await TestSupport.runGit(
            ["remote", "add", "origin", "https://github.com/octocat/Example.git"],
            in: forkPath,
        )

        let fork = try await service.cloneRepository(fullName: "octocat/Example")
        #expect(fork.path == forkPath)
        #expect(github.commands.isEmpty)

        let upstream = try await service.cloneRepository(fullName: "example-org/Example")
        #expect(upstream.name == "example-org-Example")
        #expect(upstream.path == world.paths.repositoriesDirectory + "/example-org-Example")
        #expect(github.commands == [["gh", "repo", "clone", "example-org/Example", "example-org-Example"]])
    }
}
