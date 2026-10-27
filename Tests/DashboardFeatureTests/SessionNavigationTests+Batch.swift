import AgentIDEData
import AgentIDEDomain
@testable import DashboardFeature
import Foundation
import Testing

extension SessionNavigationTests {
    @Test
    func `a failed fetch still tries each other selected repository once`() async throws {
        let runner = BatchRunner()
        let fixture = Fixture(runner: runner)
        defer { fixture.close() }
        let first = try #require(fixture.model.groups.first?.items.first)
        let linked = Fixture.item("linked", repository: fixture.repository)
        let other = Fixture.item("other", repository: Repository(name: "other", path: fixture.root + "/other"))
        let items = [first, linked, other]
        fixture.model.groups[0].items = items
        await fixture.model.performBatch(.fetch, items: items)
        #expect(await runner.commands.map(\.path) == [first.worktree.repositoryPath, other.worktree.repositoryPath])
        #expect(fixture.model.batchAction == nil)
        #expect(fixture.model.batchProgress == nil)
    }

    @Test
    func `batch cleanup continues past dirty and unmerged work without forcing`() async {
        let runner = BatchRunner()
        let fixture = Fixture(runner: runner)
        defer { fixture.close() }
        let dirty = Fixture.item("dirty", repository: fixture.repository)
        let unmerged = Fixture.item("unmerged", repository: fixture.repository)
        fixture.model.groups = [
            RepositoryGroup(repository: fixture.repository, items: [dirty, unmerged], defaultBranch: "main"),
        ]
        await fixture.model.performBatch(.cleanUp, items: [dirty, unmerged])
        let commands = await runner.commands
        #expect(commands.count == 3)
        #expect(commands.filter { $0.arguments.contains("status") }.map(\.path) == [dirty.id, unmerged.id])
        #expect(commands.last?.arguments.contains("merge-base") == true)
        #expect(commands.contains { $0.arguments.contains("remove") || $0.arguments.contains("--force") } == false)
        #expect(fixture.model.groups[0].items == [dirty, unmerged])
        #expect(fixture.model.batchAction == nil)
    }
}

// MARK: - BatchRunner

private actor BatchRunner: ProcessRunner {
    var commands: [(arguments: [String], path: String?)] = []

    func run(
        _ arguments: [String],
        workingDirectory: String?,
        environment _: [String: String],
        outputLimit _: Int?,
    ) -> ProcessResult {
        commands.append((arguments, workingDirectory))
        if arguments.contains("status") {
            return ProcessResult(
                status: 0,
                standardOutput: workingDirectory?.hasSuffix("/dirty") == true ? "? file\u{0}" : "",
                standardError: "",
            )
        }
        return ProcessResult(status: 1, standardOutput: "", standardError: "Unavailable")
    }
}
