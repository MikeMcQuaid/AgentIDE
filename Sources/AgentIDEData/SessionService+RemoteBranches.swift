import AgentIDEDomain
import Foundation

/// Opening a branch that already exists on origin as a worktree of
/// its own, split from the prompt sources for length.
public extension SessionService {
    /// Origin's branches a new worktree can check out, leaving out
    /// the default branch; `fetching` first refreshes origin when the
    /// last fetch is over a minute old, and a failed fetch still
    /// lists what was fetched before.
    func remoteBranches(repository: Repository, fetching: Bool) async -> [RemoteBranch] {
        if fetching {
            try? await fetchIfStale(repositoryPath: repository.path)
        }
        let defaultBranch = await defaultBranchName(of: repository)
        return await git.remoteBranches(repositoryPath: repository.path)
            .filter { $0 != defaultBranch }
            .map(RemoteBranch.init)
    }

    /// Checks a branch on origin out as a worktree tracking it, where
    /// a new branch of that name would go, after a fetch at most a
    /// minute old, and returns its path. No agent starts in it. The
    /// path is numbered when taken: flattening the name's slashes
    /// gives `a/b` and `a-b` one directory.
    func openRemoteBranch(_ branch: String, repository: Repository) async throws -> String {
        try await fetchIfStale(repositoryPath: repository.path)
        guard await git.refExists(worktreePath: repository.path, ref: "refs/remotes/origin/" + branch) else {
            throw SessionServiceError("`" + branch + "` is no longer on origin; choose another branch.")
        }

        let basePath = worktreeContainer(repository: repository) + "/" + branch.replacing("/", with: "-")
        var path = basePath
        var suffix = 2
        while FileManager.default.fileExists(atPath: path) {
            path = basePath + "-" + String(suffix)
            suffix += 1
        }
        await progress("Checking out `" + branch + "` from origin at `" + path + "`")
        try await git.addRemoteBranchWorktree(repository: repository, branch: branch, at: path)
        await progress("Worktree ready at `" + path + "`")
        return path
    }
}
