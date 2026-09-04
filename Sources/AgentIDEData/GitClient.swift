import AgentIDEDomain
import Foundation

/// Runs hardened git commands against guest-writable repositories.
/// Every invocation neutralises config a hostile repository could use
/// to execute code as the host user.
public struct GitClient: Sendable {
    // MARK: Lifecycle

    /// Creates the client. `isOnline` is the shared reading of
    /// whether the machine has a route, which the commands that
    /// reach a remote are refused without; tests replace it.
    @preconcurrency
    public init(
        runner: any ProcessRunner,
        isOnline: @escaping @Sendable () -> Bool = { NetworkMonitor.shared.isOnline },
    ) {
        self.runner = runner
        self.isOnline = isOnline
    }

    // MARK: Public

    /// Parses `@@ -a,b +c,d @@` hunk headers into the new file's
    /// changed line numbers; a pure deletion marks the line after it.
    public static func changedLines(fromUnifiedDiff diff: String) -> Set<Int> {
        var lines = Set<Int>()
        for line in diff.split(separator: "\n") where line.hasPrefix("@@") {
            guard let added = line.split(separator: " ").first(where: { $0.hasPrefix("+") }) else {
                continue
            }

            let parts = added.dropFirst().split(separator: ",")
            guard let start = Int(parts.first ?? "") else {
                continue
            }

            let count = parts.count > 1 ? Int(parts[1]) ?? 1 : 1
            if count == 0 {
                lines.insert(max(1, start))
            } else {
                for changed in start ..< (start + count) {
                    lines.insert(changed)
                }
            }
        }
        return lines
    }

    /// Lists repositories directly under a directory, skipping
    /// symlinked aliases so each checkout appears exactly once.
    public func repositories(under root: String) -> [Repository] {
        let manager = FileManager.default
        let names = (try? manager.contentsOfDirectory(atPath: root)) ?? []
        return names.sorted().compactMap { name in
            let path = root + "/" + name
            let attributes = try? manager.attributesOfItem(atPath: path)
            guard attributes?[.type] as? FileAttributeType != .typeSymbolicLink,
                  manager.fileExists(atPath: path + "/.git")
            else {
                return nil
            }

            return Repository(name: name, path: path)
        }
    }

    /// Lists a repository's linked worktrees. Git always lists the
    /// main checkout first, so it is skipped by position rather than
    /// by path, which canonicalisation can make unequal.
    public func worktrees(of repository: Repository) async throws -> [Worktree] {
        let output = try await git(["worktree", "list", "--porcelain"], in: repository.path).standardOutput
        var path: String?
        var branch: String?
        var index = -1
        var results = [Worktree]()

        func flush() {
            guard let currentPath = path, index > 0 else {
                return
            }

            results.append(Worktree(
                repositoryName: repository.name,
                repositoryPath: repository.path,
                // A worktree with no branch line is detached, which
                // is how git leaves one throughout a rebase. Its
                // directory is named for its branch, which is what it
                // was and will be again; requiring the branch line
                // dropped the worktree from the sidebar mid-rebase,
                // and taking its row away killed the shell running
                // in it.
                branch: branch ?? URL(fileURLWithPath: currentPath).lastPathComponent,
                path: currentPath,
            ))
        }

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("worktree ") {
                flush()
                path = String(line.dropFirst("worktree ".count))
                branch = nil
                index += 1
            } else if line.hasPrefix("branch refs/heads/") {
                branch = String(line.dropFirst("branch refs/heads/".count))
            }
        }
        flush()
        return results
    }

    /// How many commits the worktree is ahead of and behind a base
    /// ref, nil when the refs cannot be compared.
    public func aheadBehind(worktreePath: String, baseRef: String) async -> (ahead: Int, behind: Int)? {
        let result = try? await git(
            ["rev-list", "--left-right", "--count", baseRef + "...HEAD"],
            in: worktreePath,
            allowFailure: true,
        )
        guard let result, result.succeeded else {
            return nil
        }

        // `--left-right --count` prints exactly "behind<TAB>ahead".
        let counts = result.standardOutput
            .split(whereSeparator: \.isWhitespace)
            .compactMap { Int($0) }
        guard let behind = counts.first, let ahead = counts.dropFirst().first else {
            return nil
        }

        return (ahead: ahead, behind: behind)
    }

    /// Creates a worktree with a new branch based on `HEAD`.
    public func createWorktree(repository: Repository, branch: String, at path: String) async throws {
        try await git(["worktree", "add", "-b", branch, path, "HEAD"], in: repository.path)
    }

    /// Adds a detached worktree, for flows that create the branch
    /// afterwards, like `gh pr checkout`.
    public func addDetachedWorktree(repository: Repository, at path: String) async throws {
        try await git(["worktree", "add", "--detach", path, "HEAD"], in: repository.path)
    }

    /// Whether a branch name already exists.
    public func branchExists(repository: Repository, branch: String) async -> Bool {
        let result = try? await git(
            ["rev-parse", "--verify", "--quiet", "refs/heads/" + branch],
            in: repository.path,
            allowFailure: true,
        )
        return result?.succeeded ?? false
    }

    /// A tracked file's committed content, for files a working
    /// copy does not hold: the Homebrew taps are sparse checkouts
    /// carrying only their formulae, so what git knows is the only
    /// way to read their pull request template.
    public func trackedFile(worktreePath: String, path: String) async -> String? {
        let result = try? await git(["show", "HEAD:" + path], in: worktreePath, allowFailure: true)
        guard let result, result.succeeded else {
            return nil
        }

        return result.standardOutput.isEmpty ? nil : result.standardOutput
    }

    /// Whether the worktree has uncommitted changes.
    /// Whether the worktree has uncommitted work: the one reading
    /// that cannot be answered for a whole repository at once, since
    /// it is about the directory rather than the branch. Renames are
    /// not looked for: the answer is whether anything changed, and
    /// pairing up what moved is work nobody here reads.
    public func isDirty(worktreePath: String) async -> Bool {
        let output = try? await git(
            ["status", "--porcelain", "--no-renames"],
            in: worktreePath,
        ).standardOutput
        return output?.isEmpty == false
    }

    /// How many commits the worktree's branch is ahead of its
    /// upstream, nil when it has no upstream.
    public func aheadOfUpstream(worktreePath: String) async -> Int? {
        await upstreamCount(range: "@{upstream}..HEAD", worktreePath: worktreePath)
    }

    /// Commits the upstream has that the checked-out branch lacks;
    /// nil without an upstream.
    public func behindUpstream(worktreePath: String) async -> Int? {
        await upstreamCount(range: "HEAD..@{upstream}", worktreePath: worktreePath)
    }

    /// The one-based line numbers of a file changed against HEAD,
    /// staged or not, for the editor's gutter markers.
    public func changedLineNumbers(worktreePath: String, file: String) async -> Set<Int> {
        let result = try? await git(
            ["diff", "HEAD", "--unified=0", "--", file],
            in: worktreePath,
            allowFailure: true,
        )
        return Self.changedLines(fromUnifiedDiff: result?.standardOutput ?? "")
    }

    /// When the branch last committed, in seconds since 1970.
    public func lastCommitDate(worktreePath: String) async -> Int {
        let result = try? await git(["log", "-1", "--format=%ct"], in: worktreePath, allowFailure: true)
        return Int(result?.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
    }

    /// Fetches and prunes every remote.
    public func fetch(repositoryPath: String) async throws {
        await RepositoryFacts.shared.forget(repositoryPath)
        try await git(["fetch", "--all", "--prune"], in: repositoryPath)
    }

    /// Fetches origin and hard-resets the checkout to a ref, for
    /// main checkouts that should mirror the remote. The caller
    /// resolves the ref: `origin/HEAD` is a symbolic name a clone
    /// need never have been given, and resetting to one git cannot
    /// resolve fails where naming the branch works.
    public func fetchAndReset(repositoryPath: String, onto ref: String) async throws {
        try await git(["fetch", "origin"], in: repositoryPath)
        try await git(["reset", "--hard", ref], in: repositoryPath)
    }

    /// Rebases a branch onto a ref, re-signing every replayed
    /// commit; failure or conflict aborts the rebase so the worktree
    /// is left exactly as it was. The caller fetches first and picks
    /// the ref. The branch is named rather than left to whichever
    /// the worktree holds, which is not always the one on screen.
    public func rebaseSigned(worktreePath: String, branch: String, onto ref: String) async throws {
        do {
            var arguments = ["rebase", "--force-rebase"]
            if AppSettings.requiresSignedCommits {
                arguments.append("--gpg-sign")
            }
            try await git(arguments + [ref, branch], in: worktreePath)
        } catch {
            _ = try? await git(["rebase", "--abort"], in: worktreePath, allowFailure: true)
            throw error
        }
    }

    /// Reverse-applies a patch to the index and worktree together.
    public func applyReverse(patch: String, worktreePath: String) async throws {
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("agentide-reject-" + UUID().uuidString + ".patch")
        try patch.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        try await git(["apply", "--check", "-R", url.path], in: worktreePath)
        try await git(["apply", "-R", "--index", url.path], in: worktreePath)
    }

    /// Amends the last commit, optionally replacing its message.
    public func amend(worktreePath: String, message: String?) async throws {
        var arguments = ["commit", "--amend"]
        if let message {
            arguments += ["-m", message]
        } else {
            arguments.append("--no-edit")
        }
        try await git(arguments, in: worktreePath)
    }

    /// The last commit's subject and body.
    public func lastCommitMessage(worktreePath: String) async throws -> String {
        try await commitMessage(worktreePath: worktreePath, commit: "HEAD")
    }

    /// One commit's full message, named by anything git resolves.
    public func commitMessage(worktreePath: String, commit: String) async throws -> String {
        try await git(["log", "-1", "--format=%B", commit], in: worktreePath)
            .standardOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Stages everything and commits it.
    public func commitAll(worktreePath: String, message: String) async throws {
        try await git(["add", "-A"], in: worktreePath)
        try await git(["commit", "-m", message], in: worktreePath)
    }

    /// Commits named paths and leaves the rest of the worktree
    /// alone. The paths are staged first, since a commit given a
    /// pathspec refuses a path git has never seen, and named again
    /// on the commit, so whatever else was staged stays staged: a
    /// selective commit must not sweep up what the agent left in
    /// the index.
    public func commit(worktreePath: String, paths: [String], message: String) async throws {
        guard paths.isEmpty == false else {
            return
        }

        try await git(["add", "--"] + paths, in: worktreePath)
        try await git(["commit", "-m", message, "--"] + paths, in: worktreePath)
    }

    /// Pushes the branch, creating its upstream.
    /// Removes a worktree and deletes its branch; the archive bundle
    /// keeps the commits recoverable. Pruning drops any stale
    /// bookkeeping so the listing never shows a removed worktree.
    public func removeWorktree(repository: Repository, worktreePath: String, branch: String) async throws {
        // A directory that has already gone is nothing to remove,
        // and asking git to would fail the whole call; pruning and
        // forgetting below still finish the job. Every other refusal
        // is thrown on purpose: a worktree git does not know, or one
        // holding files the host user cannot delete, both land in
        // the caller's fallback, which removes the directory as its
        // owner and then prunes.
        if FileManager.default.fileExists(atPath: worktreePath) {
            try await git(["worktree", "remove", "--force", worktreePath], in: repository.path)
        }
        try await forgetWorktree(repository: repository, branch: branch)
    }

    /// Removes a worktree and deletes its branch the way git itself
    /// judges safe: no `--force`, and `-d` rather than `-D`, so git
    /// refuses a dirty worktree or an unmerged branch even if the
    /// caller's own checks were wrong or raced.
    public func removeMergedWorktree(repository: Repository, worktreePath: String, branch: String) async throws {
        try await git(["worktree", "remove", worktreePath], in: repository.path)
        try await git(["worktree", "prune"], in: repository.path)
        try await git(["branch", "-d", branch], in: repository.path)
    }

    /// Prunes gone worktrees and deletes the branch, the git-side
    /// half of removal for callers that deleted the files another
    /// way.
    public func forgetWorktree(repository: Repository, branch: String) async throws {
        try await git(["worktree", "prune"], in: repository.path)
        // A branch that is not there is the state this was asking
        // for: a worktree whose creation failed part way has none,
        // and refusing to finish left the row undeletable.
        try await git(["branch", "-D", branch], in: repository.path, allowFailure: true)
    }

    // MARK: Internal

    /// Runs git with the hardening flags prepended; internal so the
    /// cross-file length-split extensions can reach it.
    @discardableResult
    func git(
        _ arguments: [String],
        in directory: String?,
        allowFailure: Bool = false,
    ) async throws -> ProcessResult {
        // Only the commands that reach a remote need the network;
        // reading the worktree must go on working without one,
        // since a stale answer beats no answer while the route is
        // gone.
        if let remoteWork = arguments.first, Self.remoteCommands.contains(remoteWork), isOnline() == false {
            throw OfflineError(doing: "git " + remoteWork)
        }

        // `--no-optional-locks` so a read never takes the index
        // lock an agent's own git may be holding in the same
        // worktree, and never writes a refreshed index of its own.
        let argv = ["git", "--no-optional-locks"] + Self.hardening + arguments
        let result = try await runner.run(argv, workingDirectory: directory, environment: [:])
        guard result.succeeded || allowFailure else {
            throw CommandError(command: "git " + arguments.joined(separator: " "), result: result)
        }

        return result
    }

    // MARK: Private

    /// Config a compromised repository could abuse, forced off, plus
    /// user diff prefix preferences that would break the a/b paths
    /// the diff parser and patch builder expect.
    private static let hardening = [
        "-c", "core.fsmonitor=",
        "-c", "core.sshCommand=",
        "-c", "core.hooksPath=/dev/null",
        "-c", "core.pager=cat",
        "-c", "protocol.ext.allow=never",
        "-c", "diff.mnemonicPrefix=false",
        "-c", "diff.noprefix=false",
    ]

    /// The subcommands that talk to a remote, and so are the only
    /// ones a machine with no route is refused.
    private static let remoteCommands: Set<String> = ["fetch", "push", "pull", "clone", "ls-remote"]

    private let runner: any ProcessRunner
    private let isOnline: @Sendable () -> Bool

    private func upstreamCount(range: String, worktreePath: String) async -> Int? {
        let result = try? await git(["rev-list", "--count", range], in: worktreePath, allowFailure: true)
        guard let result, result.succeeded else {
            return nil
        }

        return Int(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
