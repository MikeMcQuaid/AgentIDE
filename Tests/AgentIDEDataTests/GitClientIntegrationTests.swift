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
    }

    @Test
    func `bundles recreate deleted branches`() async throws {
        let root = try TestSupport.temporaryDirectory("bundle")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let repoPath = root + "/repo"
        try await TestSupport.makeRepository(at: repoPath)
        let repository = Repository(name: "repo", path: repoPath)
        let worktreePath = root + "/wt"
        try await git.createWorktree(repository: repository, branch: "agent/keep", at: worktreePath)
        try "kept\n".write(toFile: worktreePath + "/kept.txt", atomically: true, encoding: .utf8)
        try await git.commitAll(worktreePath: worktreePath, message: "Keep")

        let bundle = root + "/branch.bundle"
        try await git.bundle(worktreePath: worktreePath, branch: "agent/keep", to: bundle)
        try await git.removeWorktree(repository: repository, worktreePath: worktreePath, branch: "agent/keep")
        #expect(await git.branchExists(repository: repository, branch: "agent/keep") == false)

        try await git.fetchBranch(repository: repository, fromBundle: bundle, branch: "agent/keep")
        #expect(await git.branchExists(repository: repository, branch: "agent/keep"))
        try await git.addWorktree(repository: repository, branch: "agent/keep", at: worktreePath)
        #expect(FileManager.default.fileExists(atPath: worktreePath + "/kept.txt"))
    }

    // MARK: Private

    private let git: GitClient = .init(runner: FoundationProcessRunner())
}
