import SanductorDomain

extension SessionService {
    func autofixConflictBase(target: AutofixDriver.Target, summary: PullRequestSummary) async throws -> String? {
        guard summary.mergeable == "CONFLICTING", summary.baseBranch.isEmpty == false else {
            return nil
        }

        try await fetchIfStale(repositoryPath: target.worktree.repositoryPath, workingDirectory: target.worktree.path)
        guard let base = await git.commitHash(
            of: "refs/remotes/origin/" + summary.baseBranch, worktreePath: target.worktree.path,
        ) else {
            throw SessionServiceError("Waiting for the fetched target branch: origin/" + summary.baseBranch)
        }

        return await git.isAncestor(base, of: "HEAD", worktreePath: target.worktree.path) ? nil : base
    }
}
