import AgentIDEDomain
import DashboardFeature
import Foundation
import Testing

/// The sidebar keeps rows one reading lost, so the panes they hold
/// open, and the shells running in those panes, only close when the
/// worktree really goes away.
@MainActor
struct RowRetentionTests {
    // MARK: Internal

    @Test
    func `keeps a row git stopped listing and drops a deleted one`() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let repositoryPath = try makeDirectory(in: root, named: "repo")
        let rebasing = try makeDirectory(in: root, named: "rebasing")
        let deleted = root + "/deleted"

        let previous = [group(repositoryPath: repositoryPath, paths: [repositoryPath, rebasing, deleted])]
        // A rebase detaches the worktree, which git omits from its
        // own listing, and the deleted one is genuinely gone.
        let next = [group(repositoryPath: repositoryPath, paths: [repositoryPath])]

        let merged = DashboardModel.retainingLostRows(of: previous, in: next)
        #expect(merged.flatMap(\.items).map(\.worktree.path) == [repositoryPath, rebasing])
    }

    @Test
    func `keeps a repository the listing lost and drops a removed one`() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let kept = try makeDirectory(in: root, named: "kept")
        let removed = root + "/removed"

        let previous = [
            group(repositoryPath: kept, paths: [kept]),
            group(repositoryPath: removed, paths: [removed]),
        ]
        let merged = DashboardModel.retainingLostRows(of: previous, in: [])
        #expect(merged.map(\.repository.path) == [kept])
    }

    // MARK: Private

    private func makeDirectory(in parent: String? = nil, named name: String = "retention") throws -> String {
        let path = (parent ?? NSTemporaryDirectory()) + "/" + name + (parent == nil ? UUID().uuidString : "")
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    private func group(repositoryPath: String, paths: [String]) -> RepositoryGroup {
        RepositoryGroup(
            repository: Repository(name: "repo", path: repositoryPath),
            items: paths.map { path in
                WorktreeItem(
                    worktree: Worktree(
                        repositoryName: "repo",
                        repositoryPath: repositoryPath,
                        branch: URL(fileURLWithPath: path).lastPathComponent,
                        path: path,
                    ),
                    session: nil,
                    isDirty: false,
                    aheadOfUpstream: nil,
                    hasUnread: false,
                )
            },
        )
    }
}
