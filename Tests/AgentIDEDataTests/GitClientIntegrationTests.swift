import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

/// Exercises the git adapter against real repositories in temporary
/// directories, covering the review loop end to end.
struct GitClientIntegrationTests {
    // MARK: Internal

    @Test
    func `worktree lifecycle: create, list, dirty, commit and diff`() async throws {
        let root = try TestSupport.temporaryDirectory("git")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let repoPath = root + "/repo"
        try await TestSupport.makeRepository(at: repoPath)
        let repository = Repository(name: "repo", path: repoPath)
        let worktreePath = root + "/worktrees/uuid/agent-change"

        try await git.createWorktree(repository: repository, branch: "agent/change", at: worktreePath)
        let worktrees = try await git.worktrees(of: repository)
        #expect(worktrees.map(\.branch) == ["agent/change"])

        #expect(await git.isDirty(worktreePath: worktreePath) == false)
        try "new\n".write(toFile: worktreePath + "/new.txt", atomically: true, encoding: .utf8)
        #expect(await git.isDirty(worktreePath: worktreePath))

        try await git.commitAll(worktreePath: worktreePath, message: "Add new file")
        #expect(await git.isDirty(worktreePath: worktreePath) == false)
        #expect(try await git.lastCommitMessage(worktreePath: worktreePath) == "Add new file")
        #expect(try await git.lastCommitDiff(worktreePath: worktreePath).contains("+new"))
        #expect(try await git.uncommittedDiff(worktreePath: worktreePath).isEmpty)

        // An older commit reads on its own, which is what clicking a
        // line of the review's commit listing asks for.
        try "newer\n".write(toFile: worktreePath + "/newer.txt", atomically: true, encoding: .utf8)
        try await git.commitAll(worktreePath: worktreePath, message: "Add newer file")
        let older = try await git.commitDiff(worktreePath: worktreePath, commit: "HEAD~1")
        #expect(older.contains("+new"))
        #expect(older.contains("+newer") == false)
        #expect(try await git.commitMessage(worktreePath: worktreePath, commit: "HEAD~1") == "Add new file")
    }

    @Test
    func `a worktree keeps its row while detached mid-rebase`() async throws {
        let root = try TestSupport.temporaryDirectory("detached")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let repoPath = root + "/repo"
        try await TestSupport.makeRepository(at: repoPath)
        let repository = Repository(name: "repo", path: repoPath)
        let worktreePath = root + "/worktrees/uuid/sentry_errors"
        try await git.createWorktree(repository: repository, branch: "sentry_errors", at: worktreePath)

        // git detaches HEAD for the whole of a rebase, and reporting
        // no worktree took its sidebar row away, which killed the
        // shell running in it.
        try await TestSupport.runGit(["checkout", "--detach"], in: worktreePath)
        let detached = try await git.worktrees(of: repository)
        #expect(detached.map(\.path) == [worktreePath])
        // Its directory is named for the branch it will return to.
        #expect(detached.map(\.branch) == ["sentry_errors"])

        try await TestSupport.runGit(["checkout", "sentry_errors"], in: worktreePath)
        let reattached = try await git.worktrees(of: repository)
        #expect(reattached.map(\.branch) == ["sentry_errors"])
    }

    @Test
    func `per-line rejection reverses only the selected change and amends`() async throws {
        let root = try TestSupport.temporaryDirectory("reject")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let repoPath = root + "/repo"
        try await TestSupport.makeRepository(at: repoPath)
        try "one\ntwo\nthree\nfour\n".write(toFile: repoPath + "/f.txt", atomically: true, encoding: .utf8)
        try await TestSupport.runGit(["add", "-A"], in: repoPath)
        try await TestSupport.runGit(["commit", "-q", "-m", "Base"], in: repoPath)
        try "one\nTHREE\nfour\n".write(toFile: repoPath + "/f.txt", atomically: true, encoding: .utf8)
        try await TestSupport.runGit(["add", "-A"], in: repoPath)
        try await TestSupport.runGit(["commit", "-q", "-m", "Change"], in: repoPath)

        let diff = try await git.lastCommitDiff(worktreePath: repoPath)
        let file = try #require(DiffParser.parse(diff).first)
        let deletionIndex = try #require(
            file.hunks[0].lines.firstIndex { $0.kind == .deletion && $0.content == "two" },
        )
        let selection = [DiffSelection(hunkIndex: 0, lineIndex: deletionIndex)]
        let patch = try #require(PatchBuilder.reversePatch(file: file, selection: Set(selection)))

        try await git.applyReverse(patch: patch, worktreePath: repoPath)
        try await git.amend(worktreePath: repoPath, message: nil)

        let content = try String(contentsOfFile: repoPath + "/f.txt", encoding: .utf8)
        #expect(content == "one\ntwo\nTHREE\nfour\n")
        #expect(try await git.lastCommitDiff(worktreePath: repoPath).contains("-two") == false)
        #expect(await git.isDirty(worktreePath: repoPath) == false)
    }

    @Test
    func `rejection works for a hunk far from the start of a file`() async throws {
        let root = try TestSupport.temporaryDirectory("reject-deep")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let repoPath = root + "/repo"
        try await TestSupport.makeRepository(at: repoPath)
        let base = (1 ... 40).map { "line\($0)" }.joined(separator: "\n") + "\n"
        try base.write(toFile: repoPath + "/f.txt", atomically: true, encoding: .utf8)
        try await TestSupport.runGit(["add", "-A"], in: repoPath)
        try await TestSupport.runGit(["commit", "-q", "-m", "Base"], in: repoPath)
        // Change a line deep in the file so the hunk's old and new starts
        // are well past line 1.
        let changed = base.replacing("line25", with: "LINE25")
        try changed.write(toFile: repoPath + "/f.txt", atomically: true, encoding: .utf8)
        try await TestSupport.runGit(["add", "-A"], in: repoPath)
        try await TestSupport.runGit(["commit", "-q", "-m", "Change"], in: repoPath)

        let diff = try await git.lastCommitDiff(worktreePath: repoPath)
        let file = try #require(DiffParser.parse(diff).first)
        #expect((file.hunks.first?.newStart ?? 0) > 1)
        // Reject the whole substitution, so line25 is restored.
        let selection = Set(file.hunks[0]
            .lines
            .indices
            .filter { file.hunks[0].lines[$0].kind != .context }
            .map { DiffSelection(hunkIndex: 0, lineIndex: $0) })
        let patch = try #require(PatchBuilder.reversePatch(file: file, selection: selection))

        try await git.applyReverse(patch: patch, worktreePath: repoPath)
        let content = try String(contentsOfFile: repoPath + "/f.txt", encoding: .utf8)
        #expect(content.contains("\nline25\n"))
        #expect(content.contains("LINE25") == false)
    }

    @Test
    func `rejection works when an earlier hunk shifts later line numbers`() async throws {
        let root = try TestSupport.temporaryDirectory("reject-shift")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let repoPath = root + "/repo"
        try await TestSupport.makeRepository(at: repoPath)
        let base = (1 ... 40).map { "line\($0)" }.joined(separator: "\n") + "\n"
        try base.write(toFile: repoPath + "/f.txt", atomically: true, encoding: .utf8)
        try await TestSupport.runGit(["add", "-A"], in: repoPath)
        try await TestSupport.runGit(["commit", "-q", "-m", "Base"], in: repoPath)
        // Insert two lines near the top and change one near the bottom, so
        // the second hunk's old and new starts differ by two.
        let changed = base
            .replacing("line3\n", with: "line3\nINSERTED_A\nINSERTED_B\n")
            .replacing("line30", with: "LINE30")
        try changed.write(toFile: repoPath + "/f.txt", atomically: true, encoding: .utf8)
        try await TestSupport.runGit(["add", "-A"], in: repoPath)
        try await TestSupport.runGit(["commit", "-q", "-m", "Change"], in: repoPath)

        let diff = try await git.lastCommitDiff(worktreePath: repoPath)
        let file = try #require(DiffParser.parse(diff).first)
        let lower = try #require(file.hunks.last)
        #expect(lower.oldStart != lower.newStart)
        let lowerIndex = file.hunks.count - 1
        let selection = Set(lower.lines
            .indices
            .filter { lower.lines[$0].kind != .context }
            .map { DiffSelection(hunkIndex: lowerIndex, lineIndex: $0) })
        let patch = try #require(PatchBuilder.reversePatch(file: file, selection: selection))

        try await git.applyReverse(patch: patch, worktreePath: repoPath)
        let content = try String(contentsOfFile: repoPath + "/f.txt", encoding: .utf8)
        #expect(content.contains("\nline30\n"))
        #expect(content.contains("LINE30") == false)
        // The unrejected top insertion is untouched.
        #expect(content.contains("INSERTED_A"))
    }

    @Test
    func `parses github full names from origin urls`() async throws {
        let root = try TestSupport.temporaryDirectory("names")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let repoPath = root + "/repo"
        try await TestSupport.makeRepository(at: repoPath)
        let repository = Repository(name: "repo", path: repoPath)

        #expect(await git.fullName(of: repository) == nil)

        try await TestSupport.runGit(
            ["remote", "add", "origin", "https://github.com/MikeMcQuaid/AgentIDE.git"],
            in: repoPath,
        )
        #expect(await git.fullName(of: repository) == "MikeMcQuaid/AgentIDE")

        try await TestSupport.runGit(
            ["remote", "set-url", "origin", "git@github.com:Homebrew/brew.git"],
            in: repoPath,
        )
        #expect(await git.fullName(of: repository) == "Homebrew/brew")
    }

    @Test
    func `one read answers for every branch in a repository`() async throws {
        let root = try TestSupport.temporaryDirectory("facts")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let path = root + "/repo"
        try await TestSupport.makeRepository(at: path)
        let bare = root + "/origin.git"
        try await TestSupport.runGit(["init", "-q", "--bare", bare], in: root)
        try await TestSupport.runGit(["remote", "add", "origin", bare], in: path)
        try await TestSupport.runGit(["push", "-q", "-u", "origin", "main"], in: path)
        try await TestSupport.runGit(["checkout", "-q", "-b", "feature"], in: path)
        try "one\n".write(toFile: path + "/one.txt", atomically: true, encoding: .utf8)
        try await TestSupport.runGit(["add", "-A"], in: path)
        try await TestSupport.runGit(["commit", "-q", "-m", "Add one"], in: path)

        // Three processes per worktree, every poll, for what git
        // works out for a whole repository in one.
        let facts = await git.branchFacts(repositoryPath: path, baseRef: "main")
        let feature = try #require(facts["feature"])
        let main = try #require(facts["main"])

        #expect(feature.ahead == 1)
        #expect(feature.behind == 0)
        #expect(feature.committedAt > 0)
        // Pushed and level: nothing to push. A branch that was never
        // pushed has no upstream to count against at all.
        #expect(main.aheadOfUpstream == 0)
        #expect(feature.aheadOfUpstream == nil)

        // The parsing itself, including an upstream that has gone.
        let parsed = GitClient.branchFacts(
            fromForEachRef: "gone-branch\trefs/remotes/origin/gone\tgone\t2 3\t100\n"
                + "ahead-branch\trefs/remotes/origin/ahead\tahead 2, behind 1\t0 0\t200\n",
        )
        #expect(parsed["gone-branch"]?.aheadOfUpstream == nil)
        #expect(parsed["gone-branch"]?.ahead == 2)
        #expect(parsed["gone-branch"]?.behind == 3)
        #expect(parsed["ahead-branch"]?.aheadOfUpstream == 2)
        #expect(parsed["ahead-branch"]?.committedAt == 200)
    }

    @Test
    func `counts commits ahead of and behind the default branch`() async throws {
        let root = try TestSupport.temporaryDirectory("counts")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let repoPath = root + "/repo"
        try await TestSupport.makeRepository(at: repoPath)
        let repository = Repository(name: "repo", path: repoPath)
        let worktreePath = root + "/worktrees/uuid/agent-count"
        try await git.createWorktree(repository: repository, branch: "agent/count", at: worktreePath)

        // One commit on the branch, one on the default branch after it.
        try "branch\n".write(toFile: worktreePath + "/branch.txt", atomically: true, encoding: .utf8)
        try await git.commitAll(worktreePath: worktreePath, message: "Branch work")
        try "main\n".write(toFile: repoPath + "/main.txt", atomically: true, encoding: .utf8)
        try await git.commitAll(worktreePath: repoPath, message: "Default work")

        let baseRef = try #require(await git.defaultBaseRef(of: repository))
        let counts = try #require(await git.aheadBehind(worktreePath: worktreePath, baseRef: baseRef))
        #expect(counts.ahead == 1)
        #expect(counts.behind == 1)

        // The whole-branch diff shows only the branch's commits, not
        // work that landed on the default branch afterwards.
        let branchDiff = try await git.branchDiff(worktreePath: worktreePath, baseRef: baseRef)
        #expect(branchDiff.contains("+branch"))
        #expect(branchDiff.contains("main.txt") == false)

        let commits = await git.branchCommits(worktreePath: worktreePath, baseRef: baseRef)
        // The branch's commit plus the decorated base row.
        #expect(commits.count == 2)
        #expect(commits.first?.contains("Branch work") == true)
        #expect(await git.lastCommitDate(worktreePath: worktreePath) > 0)
    }

    @Test
    func `push tracks a bare remote and ahead counts update`() async throws {
        let root = try TestSupport.temporaryDirectory("push")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let repoPath = root + "/repo"
        try await TestSupport.makeRepository(at: repoPath)
        try await TestSupport.run(["git", "init", "-q", "--bare", root + "/origin.git"])
        try await TestSupport.runGit(["remote", "add", "origin", root + "/origin.git"], in: repoPath)

        #expect(await git.aheadOfUpstream(worktreePath: repoPath) == nil)
        try await git.push(worktreePath: repoPath, branch: "main")
        #expect(await git.aheadOfUpstream(worktreePath: repoPath) == 0)

        try "more\n".write(toFile: repoPath + "/more.txt", atomically: true, encoding: .utf8)
        try await git.commitAll(worktreePath: repoPath, message: "More")
        #expect(await git.aheadOfUpstream(worktreePath: repoPath) == 1)

        // Amending what was pushed rewrites the remote's history,
        // which a plain push refuses as a non-fast-forward; the push
        // leases instead, so the work still lands.
        try await git.push(worktreePath: repoPath, branch: "main")
        try await TestSupport.runGit(["commit", "-q", "--amend", "-m", "More, amended"], in: repoPath)
        #expect(await git.rewritesRemoteHistory(worktreePath: repoPath, branch: "main", remote: "origin"))
        try await git.push(worktreePath: repoPath, branch: "main")
        #expect(await git.aheadOfUpstream(worktreePath: repoPath) == 0)
        #expect(try await git.lastCommitMessage(worktreePath: repoPath) == "More, amended")
    }

    // MARK: Private

    private let git: GitClient = .init(runner: FoundationProcessRunner())
}
