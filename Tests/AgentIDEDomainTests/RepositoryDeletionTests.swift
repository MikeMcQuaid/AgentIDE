import AgentIDEDomain
import Testing

struct RepositoryDeletionTests {
    // MARK: Internal

    @Test
    func `a lone, idle, clean, level checkout may be deleted and nothing else may`() {
        #expect(group([checkout()]).deletionBlocker == nil)
        #expect(group([checkout(), worktree()]).deletionBlocker == "1 worktree still exists")
        #expect(group([checkout(running: true)]).deletionBlocker == "an agent is still running")
        #expect(group([checkout(dirty: true)]).deletionBlocker == "the checkout has uncommitted or untracked files")
        #expect(
            group([checkout(ahead: nil)]).deletionBlocker == "where the checkout stands against origin is unknown",
        )
        #expect(
            group([checkout(behind: 2)]).deletionBlocker
                == "the checkout is 0 ahead and 2 behind origin's default branch",
        )
        #expect(group([]).deletionBlocker == "the checkout has not been read yet")
    }

    // MARK: Private

    private static let repository: Repository = .init(name: "repo", path: "/repositories/repo")

    private func group(_ items: [WorktreeItem]) -> RepositoryGroup {
        RepositoryGroup(repository: Self.repository, items: items)
    }

    private func checkout(
        running: Bool = false,
        dirty: Bool = false,
        ahead: Int? = 0,
        behind: Int? = 0,
    ) -> WorktreeItem {
        let session = AgentSession(
            name: "agentide--repo--main--claude",
            agent: .claudeCode,
            status: running ? .running : .finished,
            paneID: "w1:p1",
        )
        return WorktreeItem(
            worktree: Worktree(
                repositoryName: "repo",
                repositoryPath: Self.repository.path,
                branch: "main",
                path: Self.repository.path,
            ),
            session: running ? session : nil,
            isDirty: dirty,
            aheadOfUpstream: 0,
            hasUnread: false,
            aheadOfDefault: ahead,
            behindDefault: behind,
        )
    }

    private func worktree() -> WorktreeItem {
        WorktreeItem(
            worktree: Worktree(
                repositoryName: "repo",
                repositoryPath: Self.repository.path,
                branch: "fix",
                path: "/worktrees/repo/fix",
            ),
            session: nil,
            isDirty: false,
            aheadOfUpstream: 0,
            hasUnread: false,
        )
    }
}
