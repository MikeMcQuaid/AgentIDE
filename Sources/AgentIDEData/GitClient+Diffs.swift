/// The review surfaces' diffs, split from the client body for
/// length.
public extension GitClient {
    /// The worktree's uncommitted diff against `HEAD`.
    func uncommittedDiff(worktreePath: String) async throws -> String {
        var diff = try await git(["diff", "HEAD"], in: worktreePath).standardOutput
        // `git diff` never shows untracked files, so each becomes a
        // synthetic new-file diff; committing stages everything, so
        // showing them is what makes them addable.
        let untracked = try await git(
            ["ls-files", "--others", "--exclude-standard"],
            in: worktreePath,
        ).standardOutput
        for file in untracked.split(separator: "\n") {
            // Exit status 1 just means the files differ.
            let extra = try? await git(
                ["diff", "--no-index", "--", "/dev/null", String(file)],
                in: worktreePath,
                allowFailure: true,
            )
            if let output = extra?.standardOutput, output.isEmpty == false {
                diff += (diff.isEmpty || diff.hasSuffix("\n") ? "" : "\n") + output
            }
        }
        return diff
    }

    /// The last commit's diff.
    func lastCommitDiff(worktreePath: String) async throws -> String {
        try await git(["show", "--format=", "--patch", "HEAD"], in: worktreePath).standardOutput
    }

    /// Every commit on the branch against its merge base with a base
    /// ref, the whole-branch review.
    func branchDiff(worktreePath: String, baseRef: String) async throws -> String {
        try await git(["diff", baseRef + "...HEAD"], in: worktreePath).standardOutput
    }

    /// Exactly what pushing would add to an upstream ref: a two-dot
    /// diff, so commits already upstream subtract instead of
    /// widening it the way a merge-base diff would.
    func upstreamDiff(worktreePath: String, upstreamRef: String) async throws -> String {
        try await git(["diff", upstreamRef + "..HEAD"], in: worktreePath).standardOutput
    }
}
