import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

/// What a push would carry, read by patch rather than by hash: a
/// rebase onto a moved base rewrites every hash and changes nothing,
/// and the base's own changes are never the branch's work.
struct GitClientUnpushedIntegrationTests {
    // MARK: Internal

    @Test
    func `a rebase onto a moved base leaves nothing unpushed`() async throws {
        let root = try TestSupport.temporaryDirectory("unpushed")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let path = root + "/repo"
        try await TestSupport.makeRepository(at: path)
        let bare = root + "/origin.git"
        try await TestSupport.runGit(["init", "-q", "--bare", bare], in: path)
        try await TestSupport.runGit(["remote", "add", "origin", bare], in: path)
        try await TestSupport.runGit(["push", "-q", "-u", "origin", "main"], in: path)

        // The branch's own commit, pushed.
        try await TestSupport.runGit(["checkout", "-q", "-b", "feature"], in: path)
        try await commit(file: "feature.txt", message: "Add the feature", in: path)
        try await TestSupport.runGit(["push", "-q", "-u", "origin", "feature"], in: path)

        // The base moves on, and the branch follows it.
        try await TestSupport.runGit(["checkout", "-q", "main"], in: path)
        try await commit(file: "elsewhere.txt", message: "Change main", in: path)
        try await TestSupport.runGit(["checkout", "-q", "feature"], in: path)
        try await TestSupport.runGit(["rebase", "-q", "main"], in: path)

        // Every hash is new, and nothing is: the upstream holds the
        // same patch, and the base's file was never this branch's.
        #expect(await git.unpushedCommits(worktreePath: path, upstreamRef: "origin/feature", baseRef: "main").isEmpty)
        #expect(try await git.upstreamDiff(worktreePath: path, upstreamRef: "origin/feature", baseRef: "main").isEmpty)
        let lines = await git.unpushedCommitLines(worktreePath: path, upstreamRef: "origin/feature", baseRef: "main")
        #expect(lines.count == 1)
        #expect(lines.first?.contains("origin/feature") == true)

        // A commit on top is the only thing to review.
        try await commit(file: "more.txt", message: "Add more", in: path)
        let unpushed = await git.unpushedCommits(worktreePath: path, upstreamRef: "origin/feature", baseRef: "main")
        #expect(unpushed.count == 1)
        let diff = try await git.upstreamDiff(worktreePath: path, upstreamRef: "origin/feature", baseRef: "main")
        #expect(diff.contains("more.txt"))
        #expect(diff.contains("elsewhere.txt") == false)
        #expect(diff.contains("feature.txt") == false)
        let listed = await git.unpushedCommitLines(worktreePath: path, upstreamRef: "origin/feature", baseRef: "main")
        #expect(listed.count == 2)
        #expect(listed.first?.contains("Add more") == true)
    }

    @Test
    func `a base that moved before any rebase is not the branch's work either`() async throws {
        let root = try TestSupport.temporaryDirectory("behind")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let path = root + "/repo"
        try await TestSupport.makeRepository(at: path)
        let bare = root + "/origin.git"
        try await TestSupport.runGit(["init", "-q", "--bare", bare], in: path)
        try await TestSupport.runGit(["remote", "add", "origin", bare], in: path)
        try await TestSupport.runGit(["checkout", "-q", "-b", "feature"], in: path)
        try await commit(file: "feature.txt", message: "Add the feature", in: path)
        try await TestSupport.runGit(["push", "-q", "-u", "origin", "feature"], in: path)

        // The base moves on and the branch does not follow yet: the
        // bound is a ref this branch does not contain, and still
        // only what was committed here since the push is unpushed.
        try await TestSupport.runGit(["checkout", "-q", "main"], in: path)
        try await commit(file: "elsewhere.txt", message: "Change main", in: path)
        try await TestSupport.runGit(["checkout", "-q", "feature"], in: path)
        try await commit(file: "more.txt", message: "Add more", in: path)

        let unpushed = await git.unpushedCommits(worktreePath: path, upstreamRef: "origin/feature", baseRef: "main")
        #expect(unpushed.count == 1)
        let diff = try await git.upstreamDiff(worktreePath: path, upstreamRef: "origin/feature", baseRef: "main")
        #expect(diff.contains("more.txt"))
        #expect(diff.contains("feature.txt") == false)
        #expect(diff.contains("elsewhere.txt") == false)
        let listed = await git.unpushedCommitLines(worktreePath: path, upstreamRef: "origin/feature", baseRef: "main")
        #expect(listed.map { $0.contains("Add more") } == [true, false])
    }

    @Test
    func `an amended commit shows only what the amend changed`() async throws {
        let root = try TestSupport.temporaryDirectory("amended")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let path = root + "/repo"
        try await TestSupport.makeRepository(at: path)
        let bare = root + "/origin.git"
        try await TestSupport.runGit(["init", "-q", "--bare", bare], in: path)
        try await TestSupport.runGit(["remote", "add", "origin", bare], in: path)
        try await TestSupport.runGit(["checkout", "-q", "-b", "notes"], in: path)
        try await commit(file: "notes.md", message: "Draft the notes", in: path, content: "one\ntwo\n")
        try await TestSupport.runGit(["push", "-q", "-u", "origin", "notes"], in: path)

        // The pushed commit adds the whole file; so does its amended
        // twin. What pushing would change is one line, and that is
        // what there is to review, not the file over again.
        try "one\nthree\n".write(toFile: path + "/notes.md", atomically: true, encoding: .utf8)
        try await TestSupport.runGit(["commit", "-q", "-a", "--amend", "--no-edit"], in: path)

        let diff = try await git.upstreamDiff(worktreePath: path, upstreamRef: "origin/notes", baseRef: "main")
        #expect(diff.contains("-two"))
        #expect(diff.contains("+three"))
        #expect(diff.contains("+one") == false)
        // The commit itself still lists as unpushed: its patch is not
        // the one the upstream holds.
        #expect(await git.unpushedCommits(worktreePath: path, upstreamRef: "origin/notes", baseRef: "main").count == 1)
    }

    @Test
    func `a commit a rebase rewrote shows on its own`() async throws {
        let root = try TestSupport.temporaryDirectory("rewritten")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let path = root + "/repo"
        try await TestSupport.makeRepository(at: path)
        let bare = root + "/origin.git"
        try await TestSupport.runGit(["init", "-q", "--bare", bare], in: path)
        try await TestSupport.runGit(["remote", "add", "origin", bare], in: path)
        try await TestSupport.runGit(["checkout", "-q", "-b", "feature"], in: path)
        try await commit(file: "first.txt", message: "First", in: path)
        try await commit(file: "second.txt", message: "Second", in: path)
        try await TestSupport.runGit(["push", "-q", "-u", "origin", "feature"], in: path)

        // The first commit's content changes under an unchanged
        // second one, which is what resolving a conflict mid-rebase
        // leaves: one new patch in the middle of equivalent ones.
        try await TestSupport.runGit(["reset", "-q", "--hard", "HEAD~2"], in: path)
        try await commit(file: "first.txt", message: "First", in: path, content: "changed\n")
        try await TestSupport.runGit(["cherry-pick", "origin/feature"], in: path)

        let unpushed = await git.unpushedCommits(worktreePath: path, upstreamRef: "origin/feature", baseRef: "main")
        #expect(unpushed.count == 1)
        let diff = try await git.upstreamDiff(worktreePath: path, upstreamRef: "origin/feature", baseRef: "main")
        #expect(diff.contains("first.txt"))
        #expect(diff.contains("changed"))
        #expect(diff.contains("second.txt") == false)
    }

    // MARK: Private

    private let git: GitClient = .init(runner: FoundationProcessRunner())

    private func commit(file: String, message: String, in path: String, content: String = "text\n") async throws {
        try content.write(toFile: path + "/" + file, atomically: true, encoding: .utf8)
        try await TestSupport.runGit(["add", "-A"], in: path)
        try await TestSupport.runGit(["commit", "-q", "-m", message], in: path)
    }
}
