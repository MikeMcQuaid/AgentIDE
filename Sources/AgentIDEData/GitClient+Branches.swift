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
        // git keeps this in a file, and reading it is the difference
        // between a hundredth of a millisecond and a process: the
        // stack asks which branch is held on every reading of every
        // worktree, all day. The command still answers when the file
        // is not where it is expected.
        if let named = Self.headFileBranch(worktreePath: worktreePath) {
            return named
        }

        let name = await (try? git(["symbolic-ref", "HEAD"], in: worktreePath, allowFailure: true))
            .flatMap { $0.succeeded ? $0.standardOutput : nil }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "refs/heads/"
        guard let name, name.hasPrefix(prefix) else {
            return nil
        }

        return String(name.dropFirst(prefix.count))
    }

    /// The branch named in the worktree's own `HEAD`, nil when it
    /// holds a commit rather than a ref (a detached head, which is
    /// what a rebase leaves behind while it runs) or when the file
    /// cannot be found. A worktree's `.git` is a file naming the
    /// directory git keeps for it, and `HEAD` lives in there; a
    /// checkout keeps both in `.git` itself.
    static func headFileBranch(worktreePath: String) -> String? {
        let dotGit = worktreePath + "/.git"
        let pointer = (try? String(contentsOfFile: dotGit, encoding: .utf8)) ?? ""
        let marker = "gitdir: "
        var directory = dotGit
        if pointer.hasPrefix(marker) {
            let named = pointer.dropFirst(marker.count).trimmingCharacters(in: .whitespacesAndNewlines)
            // `git worktree add --relative-paths` writes a path
            // relative to this file, not to wherever the app is
            // running: resolved against the process's directory it
            // would name nothing, and every read would fall back to
            // asking git.
            directory = named.hasPrefix("/")
                ? named
                : URL(fileURLWithPath: dotGit)
                .deletingLastPathComponent()
                .appendingPathComponent(named)
                .standardizedFileURL
                .path
        }
        guard let head = try? String(contentsOfFile: directory + "/HEAD", encoding: .utf8) else {
            return nil
        }

        let prefix = "ref: refs/heads/"
        let line = head.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix(prefix) else {
            return nil
        }

        return String(line.dropFirst(prefix.count))
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

    /// Pushes the branch to a remote and tracks it there, leasing
    /// the push when the branch's history has been rewritten.
    func push(
        worktreePath: String,
        branch: String,
        remote: String = "origin",
        expectedTip: String? = nil,
    ) async throws {
        // A rewritten branch forces with a lease, and the includes
        // check refuses a remote tip never integrated here: the
        // difference between rewriting your own work and overwriting
        // someone else's. leaseRefusal carries the full story.
        var force = [String]()
        if let expectedTip {
            // Naming the tip is the confirmation the includes check
            // exists to demand: the refusal was seen, the remote
            // fetched and its version set aside, all in the app.
            force = ["--force-with-lease=" + branch + ":" + expectedTip]
        } else if await rewritesRemoteHistory(worktreePath: worktreePath, branch: branch, remote: remote) {
            force = ["--force-with-lease", "--force-if-includes"]
        }
        do {
            try await git(["push"] + force + ["--set-upstream", remote, branch], in: worktreePath)
        } catch let error as CommandError
            where error.result.standardError.contains("remote ref updated since checkout") {
            throw leaseRefusal(error, branch: branch, remote: remote)
        }
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

    /// Cuts a branch at the worktree's tip and checks it out, which
    /// is how a stack grows without a second worktree.
    func createBranch(named name: String, worktreePath: String) async throws {
        try await git(["checkout", "-b", name], in: worktreePath)
    }

    /// Every local branch in the repository, in no order of merit.
    func branches(worktreePath: String) async -> [String] {
        let result = try? await git(
            // Oldest first: when two branches sit at one commit the
            // stack keeps the one that was there first.
            ["for-each-ref", "--sort=creatordate", "--format=%(refname:short)", "refs/heads"],
            in: worktreePath,
            allowFailure: true,
        )
        return (result?.standardOutput ?? "").split(separator: "\n").map(String.init)
    }

    /// Whether one ref is in another's history, which is what makes
    /// a branch part of a stack rather than a branch of its own.
    func isAncestor(_ ancestor: String, of descendant: String, worktreePath: String) async -> Bool {
        let result = try? await git(
            ["merge-base", "--is-ancestor", ancestor, descendant],
            in: worktreePath,
            allowFailure: true,
        )
        return result?.succeeded ?? false
    }

    /// How many commits a ref carries beyond another, which orders a
    /// stack without asking anything else about it.
    func commitCount(from base: String, to ref: String, worktreePath: String) async -> Int {
        let result = try? await git(
            ["rev-list", "--count", base + ".." + ref],
            in: worktreePath,
            allowFailure: true,
        )
        return Int((result?.standardOutput ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    /// Where two refs last shared history, which is what says
    /// whether they belong to one stack: a fork point beyond the
    /// default branch means one was cut from the other.
    func mergeBase(_ first: String, _ second: String, worktreePath: String) async -> String? {
        let result = try? await git(["merge-base", first, second], in: worktreePath, allowFailure: true)
        let sha = (result?.standardOutput ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return sha.isEmpty ? nil : sha
    }

    /// A ref's commit, recorded before a stack moves so each branch
    /// is replayed from exactly where it forked.
    func tip(of ref: String, worktreePath: String) async -> String? {
        let result = try? await git(["rev-parse", ref], in: worktreePath, allowFailure: true)
        let sha = (result?.standardOutput ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return sha.isEmpty ? nil : sha
    }

    /// Checks a branch out in the worktree; the caller has already
    /// refused a dirty one or a running agent.
    func checkout(branch: String, worktreePath: String) async throws {
        try await git(["checkout", branch], in: worktreePath)
    }

    /// Moves a branch from one base to another, replaying only its
    /// own commits and signing each: `--onto` with the base the
    /// branch actually forked from is what keeps a stack from
    /// gaining its parent's commits twice. Failure aborts, leaving
    /// the branch exactly as it was.
    func rebaseSigned(branch: String, onto newBase: String, from oldBase: String, worktreePath: String) async throws {
        do {
            // Forced like the single-branch rebase: without it a
            // branch already in place fast-forwards, rewriting and
            // signing nothing, which left unsigned tips unsigned.
            var arguments = ["rebase", "--force-rebase"]
            if AppSettings.requiresSignedCommits {
                arguments.append("--gpg-sign")
            }
            try await git(
                arguments + ["--onto", newBase, oldBase, branch],
                in: worktreePath,
            )
        } catch {
            _ = try? await git(["rebase", "--abort"], in: worktreePath, allowFailure: true)
            throw error
        }
    }

    /// Puts a branch back exactly where it was, for a restack that
    /// could not finish.
    func reset(branch: String, to commit: String, worktreePath: String) async throws {
        try await git(["checkout", branch], in: worktreePath)
        try await git(["reset", "--hard", commit], in: worktreePath)
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

        return await isAncestor(ref, of: "HEAD", worktreePath: worktreePath) == false
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
    func commitMessages(worktreePath: String, range: String) async -> [String] {
        let result = try? await git(
            // Merges are history, not the branch's own work.
            ["log", "--reverse", "--no-merges", "--format=%B%x1e", range],
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
