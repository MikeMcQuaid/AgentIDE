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
    func `a placeholder that never became a worktree is forgotten, not deleted`() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let repositoryPath = try makeDirectory(in: root, named: "repo")
        let placeholder = repositoryPath + DashboardModel.placeholderMarker + "analyse_the_performance_of"

        // A creation that failed leaves a row under `.pending`,
        // which is a drawing rather than a directory: deleting one
        // asked git to remove a path that never existed and a branch
        // that was never cut, and said so in the messages.
        let rows = [group(repositoryPath: repositoryPath, paths: [repositoryPath, placeholder])]
        let kept = DashboardModel.forgetting(placeholder, in: rows)

        #expect(kept.flatMap(\.items).map(\.worktree.path) == [repositoryPath])
    }

    @Test
    func `the pending row goes the moment its worktree is listed`() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let repositoryPath = try makeDirectory(in: root, named: "repo")
        let created = try makeDirectory(in: root, named: "fix_cache_homebrew")
        let placeholder = repositoryPath + DashboardModel.placeholderMarker + "fix_this_in_this"

        // The creation names the branch itself, so the pending row
        // and the worktree never share a name: what says the work
        // has landed is the repository gaining a row at all.
        let previous = [group(repositoryPath: repositoryPath, paths: [repositoryPath, placeholder])]
        let next = [group(repositoryPath: repositoryPath, paths: [repositoryPath, created])]

        let merged = DashboardModel.retainingLostRows(of: previous, in: next)
        #expect(merged.flatMap(\.items).map(\.worktree.path) == [repositoryPath, created])
    }

    @Test
    func `the pending row stays while the creation is still working`() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let repositoryPath = try makeDirectory(in: root, named: "repo")
        let placeholder = repositoryPath + DashboardModel.placeholderMarker + "fix_this_in_this"

        // Nothing new listed yet, so the row a launch is drawing is
        // all there is to show for it.
        let previous = [group(repositoryPath: repositoryPath, paths: [repositoryPath, placeholder])]
        let next = [group(repositoryPath: repositoryPath, paths: [repositoryPath])]

        let merged = DashboardModel.retainingLostRows(of: previous, in: next)
        #expect(merged.flatMap(\.items).map(\.worktree.path).contains(placeholder))
    }

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
    func `keeps a creation placeholder, which has no directory yet`() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let repositoryPath = try makeDirectory(in: root, named: "repo")
        let placeholder = repositoryPath + DashboardModel.placeholderMarker + "fix_the_crash"

        let previous = [group(repositoryPath: repositoryPath, paths: [repositoryPath, placeholder])]
        let next = [group(repositoryPath: repositoryPath, paths: [repositoryPath])]

        let merged = DashboardModel.retainingLostRows(of: previous, in: next)
        #expect(merged.flatMap(\.items).map(\.worktree.path) == [repositoryPath, placeholder])
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
        #expect(ChecksStyle.reviewOcticonName(for: "CHANGES_REQUESTED") == "octicon-file-diff")
        #expect(ChecksStyle.reviewColour(for: "CHANGES_REQUESTED") == .red)
        // Required but not given is waiting, not failing.
        #expect(ChecksStyle.reviewOcticonName(for: "REVIEW_REQUIRED") == "clock")
        #expect(ChecksStyle.reviewColour(for: "REVIEW_REQUIRED") == .secondary)
        #expect(ChecksStyle.reviewOcticonName(for: "") == nil)
    }

    @Test
    func `every red badge a row can carry has its own glyph`() {
        // Failing checks, a reviewer asking for changes and a
        // conflict are three unrelated facts, and a row can carry
        // all three at once: sharing one crossed circle made the
        // same badge appear three times saying nothing.
        let red = [
            ChecksStyle.checksOcticonName,
            ChecksStyle.reviewOcticonName(for: "CHANGES_REQUESTED"),
            ChecksStyle.mergeableOcticonName(for: "CONFLICTING"),
        ]
        #expect(Set(red.compactMap(\.self)).count == red.count)
        #expect(ChecksStyle.mergeableOcticonName(for: "CONFLICTING") == "exclamationmark.triangle.fill")
        #expect(ChecksStyle.mergeableColour(for: "CONFLICTING") == .red)
        // A clean merge stays the merge glyph, so the pair reads as
        // one fact in two states.
        #expect(ChecksStyle.mergeableOcticonName(for: "MERGEABLE") == "octicon-git-merge")
        #expect(ChecksStyle.mergeableOcticonName(for: "UNKNOWN") == nil)

        // Each says what it is, since three red badges cannot be
        // told apart by colour.
        #expect(ChecksStyle.reviewHelp(for: "CHANGES_REQUESTED") == "A reviewer asked for changes")
        #expect(ChecksStyle.mergeableHelp(for: "CONFLICTING").contains("Conflicts with the base branch"))

        // Checks are the same dot in both rows, red or green: only
        // the colour moves, so a run finishing never reshapes a row.
        #expect(ChecksStyle.checksOcticonName == "octicon-dot-fill")
        #expect(ChecksStyle.colour(for: "FAILURE") == .red)
        #expect(ChecksStyle.colour(for: "SUCCESS") == .green)
        #expect(ChecksStyle.colour(for: "PENDING") == .orange)
    }
}
