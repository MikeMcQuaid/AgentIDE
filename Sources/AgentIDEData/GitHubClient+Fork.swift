import Foundation

/// Pushing to a repository you cannot write to. Plenty of work
/// happens in other people's repositories, where a branch belongs in
/// your own fork and the pull request comes from there.
public extension GitHubClient {
    /// Whether the branch belongs in this repository or in a fork of
    /// it, decided by what GitHub says the viewer may do here. An
    /// unanswerable question keeps the repository itself, since that
    /// is what every push did before asking was possible.
    func canPush(worktreePath: String) async -> Bool {
        let result = try? await gh(
            ["repo", "view", "--json", "viewerPermission", "--jq", ".viewerPermission"],
            in: worktreePath,
            allowFailure: true,
        )
        let permission = (result?.standardOutput ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard permission.isEmpty == false, permission != "null" else {
            return true
        }

        return Self.writingPermissions.contains(permission)
    }

    /// The account a fork would belong to, which is whoever `gh` is
    /// authenticated as; nil when it will not say.
    func viewer(worktreePath: String) async -> String? {
        let result = try? await gh(["api", "user", "--jq", ".login"], in: worktreePath, allowFailure: true)
        let login = (result?.standardOutput ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return login.isEmpty ? nil : login
    }

    /// Makes sure the viewer's fork exists and that a remote points
    /// at it, leaving both alone when they already do. `gh` picks the
    /// same protocol the repository already uses, so an SSH checkout
    /// keeps pushing over SSH.
    func ensureFork(worktreePath: String, remoteName: String) async throws {
        _ = try await gh(
            ["repo", "fork", "--clone=false", "--remote", "--remote-name", remoteName],
            in: worktreePath,
            // A fork and a remote that already exist are the wanted
            // state, and `gh` calls both of them failures.
            allowFailure: true,
        )
    }

    // MARK: Internal

    /// What GitHub calls being able to push.
    internal static let writingPermissions: Set<String> = ["ADMIN", "MAINTAIN", "WRITE"]
}
