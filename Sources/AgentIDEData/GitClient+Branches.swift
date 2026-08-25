import Foundation

/// Branch inspection and the repository-local exclude file, split
/// from the client body for length.
public extension GitClient {
    /// The branch actually checked out in a worktree, nil when
    /// detached or unreadable; agents sometimes switch away from the
    /// branch the worktree was created for. The full symbolic ref
    /// with the prefix stripped by hand, because shortening git-side
    /// (`--abbrev-ref`) answered `heads/main` whenever an agent left
    /// a stray ref named `main` elsewhere in the repository.
    func currentBranch(worktreePath: String) async -> String? {
        let name = await (try? git(["symbolic-ref", "HEAD"], in: worktreePath, allowFailure: true))
            .flatMap { $0.succeeded ? $0.standardOutput : nil }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "refs/heads/"
        guard let name, name.hasPrefix(prefix) else {
            return nil
        }

        return String(name.dropFirst(prefix.count))
    }

    /// Whether a commit carries a verifying GPG signature: good, or
    /// good from a key git does not trust. Unsigned, bad and
    /// unverifiable signatures all fail, keeping the push gate shut
    /// when in doubt.
    func isCommitSigned(worktreePath: String, ref: String = "HEAD") async -> Bool {
        let state = try? await git(["log", "-1", "--format=%G?", ref], in: worktreePath)
            .standardOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.signedStates.contains(state ?? "")
    }

    /// Whether every commit in a range carries a verifying
    /// signature; an empty range counts as signed and an unreadable
    /// one does not.
    func allCommitsSigned(worktreePath: String, range: String) async -> Bool {
        guard let output = try? await git(["log", "--format=%G?", range], in: worktreePath)
            .standardOutput
        else {
            return false
        }

        return output.split(separator: "\n").allSatisfy { Self.signedStates.contains(String($0)) }
    }

    /// Whether one ref is an ancestor of another, which is how an
    /// appended branch is told from a rewritten one.
    func isAncestor(worktreePath: String, ref: String, of descendant: String) async -> Bool {
        let result = try? await git(
            ["merge-base", "--is-ancestor", ref, descendant],
            in: worktreePath,
            allowFailure: true,
        )
        return result?.succeeded ?? false
    }

    /// Pushes the branch to a remote and tracks it there, leasing
    /// the push when the branch's history has been rewritten.
    func push(worktreePath: String, branch: String, remote: String = "origin") async throws {
        // Amending or rebasing a pushed branch rewrites what the
        // remote holds, and a plain push refuses that as a
        // non-fast-forward. The lease is what makes forcing safe:
        // it refuses if the remote moved since the last fetch. On
        // its own that trusts a stale fetch, so `--force-if-includes`
        // goes with it: the push is refused unless what it would
        // replace is already in this branch's history, which is
        // exactly the difference between a rewrite of your own work
        // and overwriting someone else's.
        let rewrites = await rewritesRemoteHistory(worktreePath: worktreePath, branch: branch, remote: remote)
        let force = rewrites ? ["--force-with-lease", "--force-if-includes"] : []
        try await git(["push"] + force + ["--set-upstream", remote, branch], in: worktreePath)
    }

    /// Checks out the default branch and pulls it: `--ff-only`, so
    /// a diverged local branch stops rather than being merged or
    /// silently rewritten, and the reason lands in the caller's
    /// error rather than in a merge commit.
    func checkoutAndPullDefault(worktreePath: String, branch: String) async throws {
        try await git(["fetch", "origin"], in: worktreePath)
        try await git(["checkout", branch], in: worktreePath)
        try await git(["pull", "--ff-only", "origin", branch], in: worktreePath)
    }

    /// Whether origin already carries the branch, after a fetch.
    func remoteBranchExists(worktreePath: String, branch: String) async -> Bool {
        await refExists(worktreePath: worktreePath, ref: "refs/remotes/origin/" + branch)
    }

    /// Whether a ref resolves here at all.
    func refExists(worktreePath: String, ref: String) async -> Bool {
        let result = try? await git(
            ["rev-parse", "--verify", "--quiet", ref],
            in: worktreePath,
            allowFailure: true,
        )
        return result?.succeeded ?? false
    }

    /// Whether pushing this branch would rewrite what the remote
    /// already has: its ref exists and is no longer an ancestor,
    /// which is what an amend or a rebase leaves behind.
    func rewritesRemoteHistory(worktreePath: String, branch: String, remote: String) async -> Bool {
        let ref = "refs/remotes/" + remote + "/" + branch
        guard await refExists(worktreePath: worktreePath, ref: ref) else {
            return false
        }

        return await isAncestor(worktreePath: worktreePath, ref: ref, of: "HEAD") == false
    }

    /// How many commits a range spans, nil when unreadable.
    func commitCount(worktreePath: String, range: String) async -> Int? {
        let result = try? await git(["rev-list", "--count", range], in: worktreePath, allowFailure: true)
        guard let result, result.succeeded else {
            return nil
        }

        return Int(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Switches the checkout to a branch.
    func checkout(worktreePath: String, branch: String) async throws {
        try await git(["checkout", branch], in: worktreePath)
    }

    /// Hard-resets the checkout to a ref; callers guard that
    /// nothing local would be lost.
    func resetHard(worktreePath: String, ref: String) async throws {
        try await git(["reset", "--hard", ref], in: worktreePath)
    }

    /// Deletes a branch with `-d`, so an unmerged branch survives.
    func deleteMergedBranch(worktreePath: String, branch: String) async {
        _ = try? await git(["branch", "-d", branch], in: worktreePath, allowFailure: true)
    }

    /// Every local branch already merged into a ref, excluding the
    /// ref itself and the checked-out branch: exactly the branches
    /// `git branch -d` would accept.
    func mergedBranches(worktreePath: String, into ref: String) async -> [String] {
        let result = try? await git(
            ["branch", "--merged", ref, "--format=%(refname:short)"],
            in: worktreePath,
            allowFailure: true,
        )
        guard let result, result.succeeded else {
            return []
        }

        let current = await currentBranch(worktreePath: worktreePath)
        let base = Self.branchName(fromRef: ref)
        return result.standardOutput
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { name in
                name.isEmpty == false && name != current && name != base
                    && name.hasPrefix("(") == false
            }
    }

    /// The bare branch name of a possibly qualified ref.
    static func branchName(fromRef ref: String) -> String {
        for prefix in ["refs/remotes/origin/", "refs/heads/", "origin/"] where ref.hasPrefix(prefix) {
            return String(ref.dropFirst(prefix.count))
        }
        return ref
    }

    /// Whether every commit of a branch is reachable from a base ref,
    /// which is what makes deleting it lossless. False when either
    /// ref is unreadable, keeping the safe path shut when in doubt.
    func isMerged(worktreePath: String, branch: String, into baseRef: String) async -> Bool {
        let result = try? await git(
            ["merge-base", "--is-ancestor", branch, baseRef],
            in: worktreePath,
            allowFailure: true,
        )
        return result?.succeeded ?? false
    }

    /// The branch's full commit messages beyond the base ref,
    /// oldest first, for drafting pull request descriptions.
    func commitMessages(worktreePath: String, baseRef: String) async -> [String] {
        let result = try? await git(
            ["log", "--reverse", "--format=%B%x1e", baseRef + "..HEAD"],
            in: worktreePath,
            allowFailure: true,
        )
        return (result?.standardOutput ?? "")
            .split(separator: "\u{1e}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    /// The branch's commits beyond the base ref, newest first, one
    /// line each.
    func branchCommits(worktreePath: String, baseRef: String) async -> [String] {
        let result = try? await git(
            ["log", "--format=%h %s%d", baseRef + "..HEAD"],
            in: worktreePath,
            allowFailure: true,
        )
        var lines = (result?.standardOutput ?? "").split(separator: "\n").map(String.init)
        // The base commit anchors the list: its ref decorations name
        // where the branch forks from the local and remote log.
        // Plain local branches pointing there are already merged, so
        // only the default and remote names survive the filter.
        let base = try? await git(
            ["log", "-1", "--format=%h %s%d", baseRef],
            in: worktreePath,
            allowFailure: true,
        )
        if let line = base?.standardOutput.split(separator: "\n").first {
            lines.append(Self.filteredBaseDecorations(String(line)))
        }
        return lines
    }

    /// Rewrites a decorated base log line, dropping local branch
    /// names other than the default: any branch pointing at the base
    /// is fully merged there, so only `origin/*`, `main`, `master`
    /// and `HEAD` arrows orient the reader.
    internal static func filteredBaseDecorations(_ line: String) -> String {
        // Decorations sit at the line's end, after the subject, so
        // the last parenthesis pair is theirs even when the subject
        // contains its own.
        guard let open = line.lastIndex(of: "("),
              let close = line[open...].firstIndex(of: ")"),
              line[line.index(after: close)...].isEmpty
        else {
            return line
        }

        let refs = line[line.index(after: open) ..< close]
            .components(separatedBy: ", ")
            .filter { ref in
                ref.hasPrefix("origin/") || ref == "main" || ref == "master" || ref.contains("HEAD")
                    || ref.hasPrefix("tag: ")
            }
        let decorations = refs.isEmpty ? "" : " (" + refs.joined(separator: ", ") + ")"
        // %d wraps decorations in " (…)", so the space before the
        // parenthesis goes with them.
        let head = line[..<open].hasSuffix(" ") ? String(line[..<open].dropLast()) : String(line[..<open])
        return head + decorations + String(line[line.index(after: close)...])
    }

    /// The `%G?` states that count as signed: a good signature, or a
    /// good one from an untrusted key.
    private static var signedStates: Set<String> {
        ["G", "U"]
    }
}
