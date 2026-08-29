import AgentIDEDomain
import Testing

/// Finding the group an item belongs to: an adopted worktree's
/// repository path names the clone that owns its branch, which no
/// group is keyed by, so membership decides first.
struct RepositoryGroupTests {
    // MARK: Internal

    @Test
    func `an adopted worktree finds its group by membership`() {
        let stray = item(path: "/w/repo/stray", repositoryPath: "/w/repo/.base")
        let plain = item(path: "/w/repo/plain", repositoryPath: "/r/repo")
        let group = RepositoryGroup(
            repository: Repository(name: "repo", path: "/r/repo"),
            items: [plain, stray],
        )
        let other = RepositoryGroup(repository: Repository(name: "other", path: "/r/other"), items: [])
        #expect([other, group].group(holding: stray)?.id == group.id)
        #expect([other, group].group(holding: plain)?.id == group.id)
        // An item no group lists still finds its home by path.
        let unlisted = item(path: "/r/repo", repositoryPath: "/r/repo")
        #expect([other, group].group(holding: unlisted)?.id == group.id)
    }

    // MARK: Private

    private func item(path: String, repositoryPath: String) -> WorktreeItem {
        WorktreeItem(
            worktree: Worktree(
                repositoryName: "repo",
                repositoryPath: repositoryPath,
                branch: "b",
                path: path,
            ),
            session: nil,
            isDirty: false,
            aheadOfUpstream: nil,
            hasUnread: false,
        )
    }
}
