import AgentIDEDomain
import Foundation

/// Pushing branches and drafting, creating and inspecting pull
/// requests.
public extension SessionService {
    /// The name of the draft file a pull request is edited in before
    /// creation; it lives in the worktree so the editor tab can open
    /// it, hidden from git status through the local exclude file.
    static let pullRequestDraftFile = ".agentide-pull-request.md"

    /// Pushes the branch to origin without opening anything.
    func push(worktree: Worktree) async throws {
        try await git.push(worktreePath: worktree.path, branch: worktree.branch)
    }

    /// The branch actually checked out in a worktree, nil when
    /// detached or unreadable.
    func currentBranch(worktreePath: String) async -> String? {
        await git.currentBranch(worktreePath: worktreePath)
    }

    /// Whether the worktree holds an unsent pull request draft.
    func hasPullRequestDraft(worktree: Worktree) -> Bool {
        FileManager.default.fileExists(atPath: worktree.path + "/" + Self.pullRequestDraftFile)
    }

    /// Writes the draft the editor opens: the last commit's subject
    /// as the title over the repository template with checkboxes
    /// prechecked and any AI disclosure filled. Returns the draft's
    /// worktree-relative path.
    func preparePullRequestDraft(worktree: Worktree, disclosure: String?) async throws -> String {
        let title = try await git.lastCommitMessage(worktreePath: worktree.path)
            .split(separator: "\n")
            .first
            .map(String.init) ?? ""
        let template = GitHubClient.pullRequestTemplate(in: worktree.path)
            .flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }
        let content = PullRequestDraft.compose(title: title, template: template, disclosure: disclosure)
        try content.write(
            toFile: worktree.path + "/" + Self.pullRequestDraftFile,
            atomically: true,
            encoding: .utf8,
        )
        try await git.excludeLocally(pattern: Self.pullRequestDraftFile, worktreePath: worktree.path)
        return Self.pullRequestDraftFile
    }

    /// Pushes and opens the pull request from the saved draft,
    /// deleting the draft on success; returns the URL.
    func createPullRequestFromDraft(worktree: Worktree) async throws -> String {
        let draftPath = worktree.path + "/" + Self.pullRequestDraftFile
        let content = try String(contentsOfFile: draftPath, encoding: .utf8)
        let (title, body) = PullRequestDraft.parse(content)
        guard title.isEmpty == false else {
            throw SessionServiceError("The pull request draft needs a title on its first line.")
        }

        try await git.push(worktreePath: worktree.path, branch: worktree.branch)
        let bodyFile = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("agentide-pr-body-" + UUID().uuidString + ".md")
            .path
        try body.write(toFile: bodyFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: bodyFile) }
        let url = try await github.createPullRequest(worktreePath: worktree.path, title: title, bodyFile: bodyFile)
        try? FileManager.default.removeItem(atPath: draftPath)
        return url
    }
}
