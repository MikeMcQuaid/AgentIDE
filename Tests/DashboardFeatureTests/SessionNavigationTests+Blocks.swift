@testable import DashboardFeature
import Foundation
import SanductorData
import SanductorDomain
import Testing

extension SessionNavigationTests {
    @Test
    func `manual blocks persist and regroup rows without changing selection`() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let item = try #require(fixture.model.groups.first?.items.first)
        fixture.model.select(item)
        var block = WorkBlock(target: SidebarTarget(item.worktree), scope: .branch, dependency: .note("Waiting"))
        #expect(fixture.model.editBlocks(block, targets: [block.target], replacing: []) == nil)
        block = try #require(fixture.model.block(for: item))
        #expect(fixture.model.statusGroups.first?.status == .blocked)
        #expect(fixture.model.selection?.id == item.id)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: URL(filePath: fixture.root + "/state.json"))
        #expect(try decoder.decode(AppMetadata.self, from: data).workBlocks == [block])
        await fixture.model.refreshWorkBlocks(force: true)
        #expect(fixture.model.block(for: item) == block)
        var replacement = WorkBlock(target: block.target, scope: .worktree, dependency: .note("Changed"))
        #expect(fixture.model.editBlocks(replacement, targets: [block.target], replacing: [block]) == nil)
        replacement = try #require(fixture.model.block(for: item))
        #expect(fixture.model.editBlocks(nil, targets: [block.target], replacing: [block]) == nil)
        #expect(fixture.model.block(for: item) == replacement)
        #expect(fixture.model.editBlocks(nil, targets: [block.target], replacing: [replacement]) == nil)
        #expect(fixture.model.statusGroups.first?.status == .branch)
    }

    @Test(arguments: ["OPEN", "CLOSED", "MERGED", "", "failure"], [true, false])
    func `only confirmed closure clears a block`(state: String, isPullRequest: Bool) async throws {
        let runner = BlockerRunner(state: state)
        let fixture = Fixture(runner: runner)
        defer { fixture.close() }
        let item = try #require(fixture.model.groups.first?.items.first)
        let target = SidebarTarget(item.worktree)
        let dependency: BlockDependency = isPullRequest
            ? .pullRequest(repositoryPath: target.repositoryPath, number: 12, title: "Dependency")
            : .issue(repositoryPath: target.repositoryPath, number: 12, title: "Dependency")
        let block = WorkBlock(target: target, scope: .worktree, dependency: dependency)
        #expect(fixture.model.editBlocks(block, targets: [target], replacing: []) == nil)
        await fixture.model.refreshWorkBlocks(force: true)
        let finished = state == "CLOSED" || (isPullRequest && state == "MERGED")
        #expect((fixture.model.block(for: item) == nil) == finished)
        #expect(await runner.commands == [
            ["gh", isPullRequest ? "pr" : "issue", "view", "12", "--json", "state", "--jq", ".state"],
        ])
    }

    @Test
    func `stale targets self dependencies and unknown repositories cannot write blocks`() throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let item = try #require(fixture.model.groups.first?.items.first)
        let target = SidebarTarget(item.worktree)
        for dependency in [
            BlockDependency.note(" "),
            .worktree(target),
            .issue(repositoryPath: "/unlisted", number: 1, title: "Issue"),
        ] {
            let block = WorkBlock(target: target, scope: .worktree, dependency: dependency)
            #expect(fixture.model.editBlocks(block, targets: [target], replacing: []) != nil)
        }
        let stale = SidebarTarget(
            repository: target.repository,
            repositoryPath: target.repositoryPath,
            branch: "old",
            path: target.path,
        )
        #expect(fixture.model.editBlocks(
            WorkBlock(target: stale, scope: .branch, dependency: .note("Wait")), targets: [stale], replacing: [],
        ) != nil)
        #expect(fixture.model.block(for: item) == nil)
    }
}

// MARK: - BlockerRunner

private actor BlockerRunner: ProcessRunner {
    // MARK: Lifecycle

    init(state: String) {
        self.state = state
    }

    // MARK: Internal

    let state: String
    var commands: [[String]] = []

    func run(
        _ arguments: [String],
        workingDirectory _: String?,
        environment _: [String: String],
        outputLimit _: Int?,
    ) -> ProcessResult {
        commands.append(arguments)
        return ProcessResult(status: state == "failure" ? 1 : 0, standardOutput: state, standardError: "Unavailable")
    }
}
