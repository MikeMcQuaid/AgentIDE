import AgentIDEDomain
import DashboardFeature
import Foundation
import SwiftUI
import TerminalUI
import Testing

// MARK: - RowRetentionTests

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

// MARK: - PullRequestBadgeTests

/// What the sidebar says about a pull request at a glance: the icons
/// and colours are the whole message, so they are pinned.
struct PullRequestBadgeTests {
    @Test
    func `each pull request state has its own icon and colour`() {
        // A queued pull request says the queue first, whatever it
        // looks like otherwise.
        #expect(ChecksStyle.stateOcticonName(state: "OPEN", isDraft: false, isQueued: true)
            == "octicon-git-merge-queue")
        // Orange, since yellow all but disappears into the sidebar.
        #expect(ChecksStyle.stateColour(state: "OPEN", isDraft: false, isQueued: true) == .orange)

        #expect(ChecksStyle.stateOcticonName(state: "MERGED", isDraft: false) == "octicon-git-merge")
        #expect(ChecksStyle.stateColour(state: "MERGED", isDraft: false) == .purple)
        #expect(ChecksStyle.stateOcticonName(state: "OPEN", isDraft: false) == "octicon-git-pull-request")
        // Purple is the merged one; an open pull request is green.
        #expect(ChecksStyle.stateColour(state: "OPEN", isDraft: false) == .green)
        #expect(ChecksStyle.stateOcticonName(state: "OPEN", isDraft: true) == "octicon-git-pull-request-draft")
        #expect(ChecksStyle.stateColour(state: "OPEN", isDraft: true) == .secondary)
        #expect(ChecksStyle.stateColour(state: "CLOSED", isDraft: false) == .red)
    }

    @Test
    func `a review shows its verdict, or that it is still waiting`() {
        #expect(ChecksStyle.reviewOcticonName(for: "APPROVED") == "octicon-check-circle-fill")
        #expect(ChecksStyle.reviewColour(for: "APPROVED") == .green)
        #expect(ChecksStyle.reviewOcticonName(for: "CHANGES_REQUESTED") == "octicon-x-circle-fill")
        #expect(ChecksStyle.reviewColour(for: "CHANGES_REQUESTED") == .red)
        // Required but not given is waiting, not failing.
        #expect(ChecksStyle.reviewOcticonName(for: "REVIEW_REQUIRED") == "clock")
        #expect(ChecksStyle.reviewColour(for: "REVIEW_REQUIRED") == .secondary)
        #expect(ChecksStyle.reviewOcticonName(for: "") == nil)
    }
}
