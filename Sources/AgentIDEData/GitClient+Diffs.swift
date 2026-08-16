/// The review surfaces' diffs, split from the client body for
/// length.
public extension GitClient {
    /// Arguments shared by every diff: `-w` drops whitespace-only
    /// changes when the review asks for it.
    private func diffOptions(ignoringWhitespace: Bool) -> [String] {
        ignoringWhitespace ? ["-w"] : []
    }

    /// The worktree's uncommitted diff against `HEAD`.
    func uncommittedDiff(worktreePath: String, ignoringWhitespace: Bool = false) async throws -> String {
        let options = diffOptions(ignoringWhitespace: ignoringWhitespace)
        var diff = try await git(["diff"] + options + ["HEAD"], in: worktreePath).standardOutput
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
                ["diff"] + options + ["--no-index", "--", "/dev/null", String(file)],
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
    func lastCommitDiff(worktreePath: String, ignoringWhitespace: Bool = false) async throws -> String {
        try await git(
            ["show", "--format=", "--patch"] + diffOptions(ignoringWhitespace: ignoringWhitespace) + ["HEAD"],
            in: worktreePath,
        ).standardOutput
    }

    /// Every commit on the branch against its merge base with a base
    /// ref, the whole-branch review.
    func branchDiff(
        worktreePath: String,
        baseRef: String,
        ignoringWhitespace: Bool = false,
    ) async throws -> String {
        try await git(
            ["diff"] + diffOptions(ignoringWhitespace: ignoringWhitespace) + [baseRef + "...HEAD"],
            in: worktreePath,
        ).standardOutput
    }

    /// Exactly what pushing would add to an upstream ref: a two-dot
    /// diff, so commits already upstream subtract instead of
    /// widening it the way a merge-base diff would.
    func upstreamDiff(
        worktreePath: String,
        upstreamRef: String,
        ignoringWhitespace: Bool = false,
    ) async throws -> String {
        try await git(
            ["diff"] + diffOptions(ignoringWhitespace: ignoringWhitespace) + [upstreamRef + "..HEAD"],
            in: worktreePath,
        ).standardOutput
    }
}
