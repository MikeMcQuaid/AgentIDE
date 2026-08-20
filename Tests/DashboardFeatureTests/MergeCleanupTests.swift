import AgentIDEDomain
@testable import DashboardFeature
import Foundation
import Testing

// MARK: - MergeCleanupTests

/// Pins the rule behind automatic cleanup: only a pull request seen
/// open at one poll and merged at the next may trigger it, never a
/// merely missing one, so a stale cache or a branch that never had a
/// pull request can never delete work.
@MainActor
struct MergeCleanupTests {
    // MARK: Internal

    @Test
    func `a branch shows its open pull request, or its last one once merged`() {
        let now = Date()
        let open = summary(number: 12, state: "OPEN")
        let merged = summary(number: 11, state: "MERGED", closedAt: now)
        #expect(DashboardModel.displayed([merged, open], now: now)?.number == 12)
        let closed = summary(number: 9, state: "CLOSED", closedAt: now)
        #expect(DashboardModel.displayed([closed, merged], now: now)?.number == 11)
        #expect(DashboardModel.displayed([], now: now) == nil)
    }

    @Test
    func `a pull request that finished long ago is a name collision, not this branch`() {
        let now = Date()
        let ancient = summary(number: 3, state: "MERGED", closedAt: now.addingTimeInterval(-Self.twoMonths))
        #expect(DashboardModel.displayed([ancient], now: now) == nil)
        let recent = summary(number: 4, state: "MERGED", closedAt: now.addingTimeInterval(-Self.oneWeek))
        #expect(DashboardModel.displayed([ancient, recent], now: now)?.number == 4)
    }

    @Test
    func `cleans up only on an observed open to merged transition`() {
        let open = summary(number: 12, state: "OPEN")
        let merged = summary(number: 12, state: "MERGED")
        #expect(DashboardModel.observedMerge(previous: open, fresh: [merged]))
    }

    @Test
    func `never cleans up on a missing, closed or different pull request`() {
        let open = summary(number: 12, state: "OPEN")
        #expect(DashboardModel.observedMerge(previous: nil, fresh: [summary(number: 12, state: "MERGED")]) == false)
        #expect(DashboardModel.observedMerge(previous: open, fresh: []) == false)
        #expect(DashboardModel.observedMerge(previous: open, fresh: [summary(number: 12, state: "CLOSED")]) == false)
        #expect(DashboardModel.observedMerge(previous: open, fresh: [summary(number: 13, state: "MERGED")]) == false)
        // A cache that already said merged saw nothing new happen.
        let alreadyMerged = summary(number: 12, state: "MERGED")
        #expect(DashboardModel.observedMerge(previous: alreadyMerged, fresh: [alreadyMerged]) == false)
    }

    // MARK: Private

    private static let twoMonths: TimeInterval = 5_184_000
    private static let oneWeek: TimeInterval = 604_800

    private func summary(number: Int, state: String, closedAt: Date? = nil) -> PullRequestSummary {
        PullRequestSummary(
            number: number,
            title: "Title",
            url: "",
            headBranch: "feature",
            mergeable: "",
            reviewDecision: "",
            checks: "",
            state: state,
            closedAt: closedAt,
        )
    }
}

// MARK: - CreationPlaceholderTests

/// Pins the provisional row a new session shows while its worktree
/// is created: named from the prompt in the branch style, and never
/// mistaken for a real worktree.
@MainActor
struct CreationPlaceholderTests {
    @Test
    func `placeholder names come from the prompt's first words`() {
        #expect(DashboardModel.placeholderName(from: "Fix the crash on launch, please") == "fix_the_crash_on")
        #expect(DashboardModel.placeholderName(from: "   ") == "new_session")
    }

    @Test
    func `placeholder items are recognised by their synthetic path`() {
        let placeholder = WorktreeItem(
            worktree: Worktree(
                repositoryName: "repo",
                repositoryPath: "/repo",
                branch: "fix_the_crash",
                path: "/repo" + DashboardModel.placeholderMarker + "fix_the_crash",
            ),
            session: nil,
            isDirty: false,
            aheadOfUpstream: nil,
            hasUnread: false,
        )
        #expect(placeholder.isPlaceholder)
        let real = WorktreeItem(
            worktree: Worktree(repositoryName: "repo", repositoryPath: "/repo", branch: "main", path: "/repo"),
            session: nil,
            isDirty: false,
            aheadOfUpstream: nil,
            hasUnread: false,
        )
        #expect(real.isPlaceholder == false)
    }
}
