/// The review surfaces' diffs, split from the client body for
/// length.
public extension GitClient {
    /// Arguments shared by every diff: `-w` drops whitespace-only
    /// changes when the review asks for it.
    /// How `git cherry` marks a commit whose patch the upstream
    /// lacks; a minus marks one it already holds under another hash.
    private static let missingUpstream = "+ "

    private func diffOptions(ignoringWhitespace: Bool) -> [String] {
        if ignoringWhitespace {
            ["-w"]
        } else {
            []
        }
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

    /// One commit's own diff, named by anything git resolves.
    func commitDiff(worktreePath: String, commit: String, ignoringWhitespace: Bool = false) async throws -> String {
        try await git(
            ["show", "--format=", "--patch"] + diffOptions(ignoringWhitespace: ignoringWhitespace) + [commit],
            in: worktreePath,
        ).standardOutput
    }

    /// The last commit's diff.
    func lastCommitDiff(worktreePath: String, ignoringWhitespace: Bool = false) async throws -> String {
        try await commitDiff(
            worktreePath: worktreePath,
            commit: "HEAD",
            ignoringWhitespace: ignoringWhitespace,
        )
    }

    /// One branch's own changes against another, which is what a
    /// stack's entry shows: three dots, so what the parent already
    /// carries never appears in the child's diff.
    func stackDiff(
        worktreePath: String,
        parent: String,
        branch: String,
        ignoringWhitespace: Bool = false,
    ) async throws -> String {
        try await git(
            ["diff"] + diffOptions(ignoringWhitespace: ignoringWhitespace) + [parent + "..." + branch],
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

    /// The commits a push would carry that the upstream does not
    /// already hold in some form: by patch rather than by hash
    /// (`git cherry`), oldest first, and only the branch's own, the
    /// base ref bounding them. A rebase onto a moved base rewrites
    /// every hash and changes no patch, so counting hashes said the
    /// whole branch was unpushed; and the base's own commits sit in
    /// the range too, so without the bound its changes read as the
    /// branch's work. A base that is not known, or does not resolve
    /// here, bounds nothing: the answer is then every commit the
    /// upstream lacks, which is right wherever the base has not
    /// moved.
    func unpushedCommits(worktreePath: String, upstreamRef: String, baseRef: String?) async -> [String] {
        var arguments = ["cherry", upstreamRef, "HEAD"]
        if let baseRef, await refExists(worktreePath: worktreePath, ref: baseRef) {
            arguments.append(baseRef)
        }
        let result = try? await git(arguments, in: worktreePath, allowFailure: true)
        return (result?.standardOutput ?? "").split(separator: "\n").compactMap { line in
            line.hasPrefix(Self.missingUpstream) ? String(line.dropFirst(Self.missingUpstream.count)) : nil
        }
    }

    /// Exactly what pushing would add that the upstream lacks: the
    /// unpushed commits' own changes and nothing else. A run of them
    /// ending at the tip, which is nearly every case, is one range
    /// diff; a commit a conflicted rebase rewrote in the middle of
    /// the branch shows on its own, since no single range holds it
    /// without the equivalent commits around it.
    func upstreamDiff(
        worktreePath: String,
        upstreamRef: String,
        baseRef: String?,
        ignoringWhitespace: Bool = false,
    ) async throws -> String {
        let commits = await unpushedCommits(worktreePath: worktreePath, upstreamRef: upstreamRef, baseRef: baseRef)
        guard let first = commits.first else {
            return ""
        }

        let options = diffOptions(ignoringWhitespace: ignoringWhitespace)
        let range = first + "^..HEAD"
        let spanned = try? await git(["rev-list", "--count", range], in: worktreePath, allowFailure: true)
        if Int(spanned?.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") == commits.count {
            return try await git(["diff"] + options + [range], in: worktreePath).standardOutput
        }

        var diff = ""
        for commit in commits {
            diff += try await git(["show", "--format="] + options + [commit], in: worktreePath).standardOutput
        }
        return diff
    }
}
