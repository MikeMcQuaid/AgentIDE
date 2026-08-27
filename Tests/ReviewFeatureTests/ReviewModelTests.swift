import AgentIDEData
import AgentIDEDomain
import Foundation
@testable import ReviewFeature
import Testing

// MARK: - CommitMessageFieldTests

/// The footer's subject and body fields split and rejoin the commit
/// message around git's blank separator line.
struct CommitMessageFieldTests {
    @Test
    func `subject and body split and rejoin around the separator`() {
        let message = "Fix the bug\n\nIt crashed.\n\n- twice"
        #expect(ReviewFooterView.subject(of: message) == "Fix the bug")
        #expect(ReviewFooterView.messageBody(of: message) == "It crashed.\n\n- twice")
        #expect(
            ReviewFooterView.message(subject: "Fix the bug", body: "It crashed.\n\n- twice") == message,
        )
        #expect(ReviewFooterView.message(subject: "Just a subject", body: "") == "Just a subject")
        #expect(ReviewFooterView.messageBody(of: "Just a subject").isEmpty)
    }
}

// MARK: - ReviewModelTests

/// Exercises the review model's scopes against a real repository, so
/// each scope button reliably changes what the pane shows.
struct ReviewModelTests {
    // MARK: Internal

    @Test
    func `scopes show their own diffs even with uncommitted changes present`() async throws {
        // The user's temporary directory, per the no-bare-/tmp rule.
        let path = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("agentide-review-" + UUID().uuidString, isDirectory: true)
            .path
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await makeRepository(at: path)
        try "committed\n".write(toFile: path + "/committed.txt", atomically: true, encoding: .utf8)
        try await runGit(["add", "-A"], in: path)
        try await runGit(["commit", "-q", "-m", "Add committed file"], in: path)
        try "dirty\n".write(toFile: path + "/dirty.txt", atomically: true, encoding: .utf8)
        try await runGit(["add", "-A"], in: path)

        let model = ReviewModel(
            worktreePath: path,
            repositoryName: "repo",
            git: GitClient(runner: FoundationProcessRunner()),
        )
        model.scope = .lastCommit
        await model.reload()
        #expect(model.files.map(\.path) == ["committed.txt"])
        #expect(model.showsUncommitted == false)

        model.scope = .uncommitted
        await model.reload()
        #expect(model.files.map(\.path) == ["dirty.txt"])
        #expect(model.showsUncommitted)

        // Untracked files show as new-file diffs, so committing can
        // include them.
        try "loose\n".write(toFile: path + "/untracked.txt", atomically: true, encoding: .utf8)
        await model.reload()
        #expect(model.files.map(\.path).sorted() == ["dirty.txt", "untracked.txt"])
    }

    @Test
    func `upstream scope gates on a pushed branch and diffs against it`() async throws {
        let path = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("agentide-upstream-" + UUID().uuidString, isDirectory: true)
            .path
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await makeRepository(at: path)

        let model = ReviewModel(
            worktreePath: path,
            repositoryName: "repo",
            git: GitClient(runner: FoundationProcessRunner()),
        )
        model.scope = .upstream
        await model.reload()
        #expect(model.hasUpstream == false)
        #expect(model.files.isEmpty)
        #expect(model.status == "This branch has not been pushed yet.")

        let bare = path + "-origin.git"
        defer { try? FileManager.default.removeItem(atPath: bare) }
        try await runGit(["init", "-q", "--bare", bare], in: path)
        try await runGit(["remote", "add", "origin", bare], in: path)
        try await runGit(["push", "-q", "-u", "origin", "main"], in: path)
        try "unpushed\n".write(toFile: path + "/unpushed.txt", atomically: true, encoding: .utf8)
        try await runGit(["add", "-A"], in: path)
        try await runGit(["commit", "-q", "-m", "Add unpushed file"], in: path)

        await model.reload()
        #expect(model.hasUpstream)
        #expect(model.files.map(\.path) == ["unpushed.txt"])
        // The unpushed commit plus the decorated base row.
        #expect(model.branchCommits.count == 2)
        #expect(model.branchCommits.first?.contains("Add unpushed file") == true)
        #expect(model.branchCommits.last?.contains("origin/main") == true)
    }

    @Test
    func `finding walks the hunks that hold a match and highlights them`() async throws {
        let path = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("agentide-find-" + UUID().uuidString, isDirectory: true)
            .path
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await makeRepository(at: path)
        try "needle here\n".write(toFile: path + "/one.txt", atomically: true, encoding: .utf8)
        try "nothing\n".write(toFile: path + "/two.txt", atomically: true, encoding: .utf8)
        try "a NEEDLE too\n".write(toFile: path + "/three.txt", atomically: true, encoding: .utf8)
        try await runGit(["add", "-A"], in: path)

        let model = ReviewModel(
            worktreePath: path,
            repositoryName: "repo",
            git: GitClient(runner: FoundationProcessRunner()),
        )
        model.scope = .uncommitted
        await model.reload()
        #expect(model.findTargets.isEmpty)
        #expect(model.findSummary.isEmpty)

        // Matching ignores case, and only the hunks holding a match
        // are walked.
        model.findQuery = "needle"
        #expect(model.findTargets.map(\.file) == ["one.txt", "three.txt"])
        #expect(model.findSummary == "1 of 2")
        #expect(model.currentFindTarget == "one.txt#0")

        model.moveFind(by: 1)
        #expect(model.currentFindTarget == "three.txt#0")
        // Walking wraps rather than stopping at the last match.
        model.moveFind(by: 1)
        #expect(model.currentFindTarget == "one.txt#0")
        model.moveFind(by: -1)
        #expect(model.currentFindTarget == "three.txt#0")

        // The renderer asks for what to tint on each line.
        #expect(model.findRanges(in: "a needle and a needle").count == 2)
        #expect(model.findRanges(in: "nothing").isEmpty)

        model.findQuery = ""
        #expect(model.findTargets.isEmpty)
        #expect(model.findRanges(in: "needle").isEmpty)
    }

    // MARK: Private

    private func makeRepository(at path: String) async throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        try await runGit(["init", "-q", "-b", "main"], in: path)
        try await runGit(["config", "user.email", "test@example.com"], in: path)
        try await runGit(["config", "user.name", "Test"], in: path)
        try "hello\n".write(toFile: path + "/README.md", atomically: true, encoding: .utf8)
        try await runGit(["add", "-A"], in: path)
        try await runGit(["commit", "-q", "-m", "Initial commit"], in: path)
    }

    private func runGit(_ arguments: [String], in directory: String) async throws {
        _ = try await FoundationProcessRunner().run(
            ["git", "-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false"] + arguments,
            workingDirectory: directory,
            environment: [:],
        )
    }
}

// MARK: - HunkCopyTests

/// Pins what a copied hunk holds: the file's own text, since the
/// displayed text stands a space in for a blank line so its change
/// colour has something to paint.
@MainActor
struct HunkCopyTests {
    @Test
    func `a copied hunk keeps blank lines blank`() {
        let hunk = DiffHunk(
            oldStart: 1,
            newStart: 1,
            lines: [
                DiffLine(kind: .context, content: "let a = 1"),
                DiffLine(kind: .addition, content: ""),
                DiffLine(kind: .addition, content: "let b = 2"),
            ],
        )
        #expect(DiffFileView.copyText(of: hunk) == "let a = 1\n\nlet b = 2")
    }
}
