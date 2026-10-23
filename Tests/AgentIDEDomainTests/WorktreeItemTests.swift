import AgentIDEDomain
import Testing

struct WorktreeItemTests {
    @Test
    func `session changes preserve branch status`() {
        let item = WorktreeItem(
            worktree: Worktree(repositoryName: "repo", repositoryPath: "/repo", branch: "feature", path: "/worktree"),
            session: nil,
            isDirty: true,
            aheadOfUpstream: 1,
            hasUnread: true,
            aheadOfDefault: 2,
            behindDefault: 3,
            behindUpstream: 4,
            revision: "base head",
        )
        #expect(item.with(session: nil).branchStatus == item.branchStatus)
        #expect(item.withoutSession().branchStatus == item.branchStatus)
        #expect(item.renamed(branch: "renamed").behindUpstream == 4)
    }
}
