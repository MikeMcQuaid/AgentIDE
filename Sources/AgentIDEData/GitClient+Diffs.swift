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

    /// Exactly what pushing would change on the remote, with the
    /// base's own movement factored out: the upstream's work
    /// replayed onto the base the branch now sits on (`git
    /// merge-tree`, a rebase done as a merge with no worktree), then
    /// diffed against `HEAD`. An amended commit shows as the lines
    /// that changed rather than the whole commit again, a plain
    /// rebase shows nothing, and the base's changes never show. A
    /// replay that conflicts, or a base that is not known, falls
    /// back to the unpushed commits' own patches.
    func upstreamDiff(
        worktreePath: String,
        upstreamRef: String,
        baseRef: String?,
        ignoringWhitespace: Bool = false,
    ) async throws -> String {
        let options = diffOptions(ignoringWhitespace: ignoringWhitespace)
        let replayed = await upstreamReplayed(
            worktreePath: worktreePath,
            upstreamRef: upstreamRef,
            baseRef: baseRef,
        )
        if let replayed {
            return try await git(["diff"] + options + [replayed, "HEAD"], in: worktreePath).standardOutput
        }

        return try await unpushedPatches(
            worktreePath: worktreePath,
            upstreamRef: upstreamRef,
            baseRef: baseRef,
            options: options,
        )
    }

    /// The upstream's tree as it would be on the branch's current
    /// base: the upstream itself when the base has not moved, else
    /// the three-way merge of the upstream and the new base over
    /// the old one, which is what a rebase does. Nil without a base
    /// to measure by, or when the replay conflicts.
    private func upstreamReplayed(worktreePath: String, upstreamRef: String, baseRef: String?) async -> String? {
        guard let baseRef, await refExists(worktreePath: worktreePath, ref: baseRef),
              let oldBase = await mergeBase(baseRef, upstreamRef, worktreePath: worktreePath),
              let newBase = await mergeBase(baseRef, "HEAD", worktreePath: worktreePath)
        else {
            return nil
        }
        guard oldBase != newBase else {
            return upstreamRef
        }

        let merged = try? await git(
            ["merge-tree", "--write-tree", "--merge-base=" + oldBase, upstreamRef, newBase],
            in: worktreePath,
            allowFailure: true,
        )
        guard let merged, merged.succeeded,
              let tree = merged.standardOutput.split(separator: "\n").first
        else {
            return nil
        }

        return String(tree)
    }

    /// The unpushed commits' own patches: a run of them ending at
    /// the tip is one range diff, and a commit a conflicted rebase
    /// rewrote in the middle of the branch shows on its own.
    private func unpushedPatches(
        worktreePath: String,
        upstreamRef: String,
        baseRef: String?,
        options: [String],
    ) async throws -> String {
        let commits = await unpushedCommits(worktreePath: worktreePath, upstreamRef: upstreamRef, baseRef: baseRef)
        guard let first = commits.first else {
            return ""
        }

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
