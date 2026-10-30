extension GitClient {
    /// Wakes the configured signer without moving HEAD or consuming staged changes.
    func warmSigning(worktreePath: String) async throws {
        let fieldCount = 3
        let commit = try await git(["show", "--no-patch", "--format=%T%n%P%n%B", "HEAD"], in: worktreePath)
            .standardOutput
            .split(separator: "\n", maxSplits: fieldCount - 1, omittingEmptySubsequences: false)
        guard commit.count == fieldCount else {
            throw SessionServiceError("Cannot read the current commit for signing")
        }

        let parents = commit[1].split(separator: " ").flatMap { ["-p", String($0)] }
        try await git(
            ["commit-tree", "-S", String(commit[0])] + parents + ["-m", String(commit[fieldCount - 1])],
            in: worktreePath,
        )
    }
}
