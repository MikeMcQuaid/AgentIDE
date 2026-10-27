import AgentIDEDomain
import Testing

struct RepositorySortTests {
    @Test
    func `priority uses the highest row and full names break ties`() {
        let repositories: [(String, RepositorySort.Key)] = [
            ("blocked", .init(name: "a/blocked", statuses: [.blocked], activity: 50)),
            ("ready", .init(name: "a/ready", statuses: [.readyToMerge], activity: 0)),
            ("working10", .init(name: "a/repo10", statuses: [.blocked, .working], activity: 0)),
            ("done", .init(name: "a/done", statuses: [.done], activity: 0)),
            ("working2", .init(name: "a/repo2", statuses: [.working, .worktree], activity: 0)),
            ("host", .init(name: "a/host", statuses: [.hostDirectory], activity: 0)),
            ("default", .init(name: "a/default", statuses: [.defaultBranch], activity: 0)),
            ("empty", .init(name: "a/empty", statuses: [], activity: 0)),
        ]
        #expect(RepositorySort.status.sorted(repositories) { $0.1 }.map(\.0)
            == ["working2", "working10", "ready", "done", "host", "blocked", "default", "empty"])
    }

    @Test
    func `name sorting includes the owner and ignores state and activity`() {
        let repositories: [(String, RepositorySort.Key)] = [
            ("z/repo", .init(name: "z/repo", statuses: [.working], activity: 50)),
            ("local", .init(name: "local", statuses: [.done], activity: 0)),
            ("A/repo", .init(name: "A/repo", statuses: [.blocked], activity: 0)),
        ]
        #expect(RepositorySort.name.sorted(repositories) { $0.1 }.map(\.0) == ["A/repo", "local", "z/repo"])
    }

    @Test
    func `recent activity puts unknown dates last with stable name ties`() {
        let repositories: [(String, RepositorySort.Key)] = [
            ("old", .init(name: "a/old", statuses: [.working], activity: 1)),
            ("unknown", .init(name: "a/unknown", statuses: [], activity: 0)),
            ("new-b", .init(name: "b/new", statuses: [.blocked], activity: 50)),
            ("new-a", .init(name: "a/new", statuses: [.done], activity: 50)),
        ]
        #expect(RepositorySort.activity.sorted(repositories) { $0.1 }.map(\.0)
            == ["new-a", "new-b", "old", "unknown"])
    }
}
