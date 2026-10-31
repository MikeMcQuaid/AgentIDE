@testable import DashboardFeature
import SanductorData
import SanductorDomain
import Testing

extension SessionNavigationTests {
    @Test
    func `a late launch failure restores its row without moving the selection`() async throws {
        let runner = FailingIssueRunner()
        let fixture = Fixture(runner: runner)
        defer { fixture.close() }
        let main = fixture.model.groups[0].items[0]
        let created = WorktreeItem(
            worktree: Worktree(
                repositoryName: fixture.repository.name,
                repositoryPath: fixture.repository.path,
                branch: "another_launch",
                path: fixture.repository.path + "/another_launch",
            ),
            session: nil,
            isDirty: false,
            aheadOfUpstream: nil,
        )
        var pending: WorktreeItem?
        await runner.beforeFailing {
            pending = fixture.model.selection
            fixture.model.groups = DashboardModel.retainingLostRows(
                of: fixture.model.groups,
                in: [RepositoryGroup(repository: fixture.repository, items: [main, created])],
            )
            fixture.model.select(created)
        }

        await fixture.model.createSession(
            fromIssue: 12, repository: fixture.repository, context: "Fix it", agent: .claudeCode,
        )

        let placeholder = try #require(pending)
        #expect(fixture.model.worktreePaths.contains(placeholder.worktree.path))
        #expect(fixture.model.launchFailure(for: placeholder) != nil)
        #expect(fixture.model.selection?.id == created.id)
        #expect(fixture.model.deletingPaths.contains(placeholder.worktree.path) == false)
        #expect(fixture.model.launchProgresses.isEmpty)
    }
}

// MARK: - FailingIssueRunner

private actor FailingIssueRunner: ProcessRunner {
    // MARK: Internal

    func beforeFailing(_ action: @escaping @MainActor @Sendable () -> Void) {
        beforeFailure = action
    }

    func run(
        _ arguments: [String],
        workingDirectory _: String?,
        environment _: [String: String],
        outputLimit _: Int?,
    ) async -> ProcessResult {
        if arguments.contains("issue"), arguments.contains("view") {
            await beforeFailure?()
            beforeFailure = nil
            return ProcessResult(status: 1, standardOutput: "", standardError: "Issue unavailable")
        }
        return ProcessResult(status: 0, standardOutput: "[]", standardError: "")
    }

    // MARK: Private

    private var beforeFailure: (@MainActor @Sendable () -> Void)?
}
