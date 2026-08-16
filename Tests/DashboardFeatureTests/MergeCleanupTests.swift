import AgentIDEDomain
@testable import DashboardFeature
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

    private func summary(number: Int, state: String) -> PullRequestSummary {
        PullRequestSummary(
            number: number,
            title: "Title",
            url: "",
            headBranch: "feature",
            mergeable: "",
            reviewDecision: "",
            checks: "",
            state: state,
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
