import AgentIDEData
import Foundation
@testable import ReviewFeature
import TerminalUI
import Testing

extension ReviewModelTests {
    @Test(arguments: [ReviewModel.Scope.lastCommit, .uncommitted, .upstream, .branch])
    func `missing worktree metadata stays quiet and recovers when restored`(scope: ReviewModel.Scope) async throws {
        let path = FileManager.default.currentDirectoryPath + "/.test-scratch/review-unavailable-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await makeRepository(at: path)
        let worktree = path + "/linked"
        try await runGit(["worktree", "add", "-b", "linked", worktree, "HEAD"], in: path)
        let pointer = try String(contentsOfFile: worktree + "/.git", encoding: .utf8)
        let marker = "unavailable-" + UUID().uuidString
        let baseRef: () -> String? = { "main" }
        let model = ReviewModel(
            worktreePath: worktree,
            repositoryName: marker,
            git: GitClient(runner: FoundationProcessRunner()),
            baseRefProvider: baseRef,
        )
        model.scope = .lastCommit
        await model.reload()
        try #require(model.files.isEmpty == false)
        model.scope = scope
        try ("gitdir: " + path + "/missing\n").write(toFile: worktree + "/.git", atomically: true, encoding: .utf8)

        await model.reload()
        await model.reload()
        #expect(model.hasLoaded)
        #expect(model.isRepositoryAvailable == false)
        #expect(model.isReadOnly)
        #expect(model.hasSomethingToCommit == false)
        #expect(model.canAmendLastCommit == false)
        #expect(ErrorLog.shared.entries.contains { $0.message.contains(marker) } == false)

        try pointer.write(toFile: worktree + "/.git", atomically: true, encoding: .utf8)
        model.scope = .lastCommit
        await model.reload()
        #expect(model.isRepositoryAvailable)
        #expect(model.commitMessage == "Initial commit")
        #expect(model.files.map(\.path) == ["README.md"])
    }

    @Test(arguments: [false, true])
    func `invalid review targets still report failures in a valid repository`(stack: Bool) async throws {
        let path = FileManager.default.currentDirectoryPath + "/.test-scratch/review-invalid-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: path) }
        try await makeRepository(at: path)
        let marker = "invalid-target-" + UUID().uuidString
        let model = ReviewModel(
            worktreePath: path,
            repositoryName: marker,
            git: GitClient(runner: FoundationProcessRunner()),
        )
        if stack {
            model.stackTarget = (parent: "main", branch: "missing")
        } else {
            model.commitTarget = "missing"
        }

        await model.reload()
        #expect(model.isRepositoryAvailable)
        #expect(ErrorLog.shared.entries.contains { $0.isError && $0.message.contains(marker) } == false)
        await model.reload()
        #expect(model.isRepositoryAvailable)
        #expect(ErrorLog.shared.entries.contains { $0.isError && $0.message.contains(marker) })
    }
}
