import AgentIDEDomain
import Foundation

/// Runs hardened git commands against guest-writable repositories.
/// Every invocation neutralises config a hostile repository could use
/// to execute code as the host user.
public struct GitClient: Sendable {
    // MARK: Lifecycle

    /// Creates a client.
    public init(runner: any ProcessRunner) {
        self.runner = runner
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
        var index = -1
        var results = [Worktree]()
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("worktree ") {
                path = String(line.dropFirst("worktree ".count))
                index += 1
            } else if line.hasPrefix("branch refs/heads/"), let currentPath = path, index > 0 {
                results.append(Worktree(
                    repositoryName: repository.name,
                    repositoryPath: repository.path,
                    branch: String(line.dropFirst("branch refs/heads/".count)),
                    path: currentPath,
                ))
            }
        }
        return results
    }

    /// The repository's GitHub `owner/name`, parsed from the origin
    /// remote, nil for non-GitHub or remoteless repositories.
    public func fullName(of repository: Repository) async -> String? {
        let result = try? await git(
            ["remote", "get-url", "origin"],
            in: repository.path,
            allowFailure: true,
        )
        guard let result, result.succeeded else {
            return nil
        }

        let url = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = url.range(of: "github.com") else {
            return nil
        }

        let path = url[range.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: ":/"))
        let components = path.split(separator: "/").map(String.init)
        guard let owner = components.first, let repo = components.dropFirst().first else {
            return nil
        }

        let name = repo.hasSuffix(".git") ? String(repo.dropLast(".git".count)) : repo
        return owner + "/" + name
    }

    /// The base ref merges are judged against: the origin's default
    /// branch when known, otherwise a local main or master.
    public func defaultBaseRef(of repository: Repository) async -> String? {
        let head = try? await git(
            ["symbolic-ref", "--short", "refs/remotes/origin/HEAD"],
            in: repository.path,
            allowFailure: true,
        )
        if let head, head.succeeded {
            return head.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for candidate in ["main", "master"] where await branchExists(repository: repository, branch: candidate) {
            return candidate
        }
        return nil
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

    /// Whether the worktree has uncommitted changes.
    public func isDirty(worktreePath: String) async -> Bool {
        let output = try? await git(["status", "--porcelain"], in: worktreePath).standardOutput
        return output?.isEmpty == false
    }

    /// How many commits the worktree's branch is ahead of its
    /// upstream, nil when it has no upstream.
    public func aheadOfUpstream(worktreePath: String) async -> Int? {
        let result = try? await git(
            ["rev-list", "--count", "@{upstream}..HEAD"],
            in: worktreePath,
            allowFailure: true,
        )
        guard let result, result.succeeded else {
            return nil
        }

        return Int(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The worktree's uncommitted diff against `HEAD`.
    public func uncommittedDiff(worktreePath: String) async throws -> String {
        try await git(["diff", "HEAD"], in: worktreePath).standardOutput
    }

    /// The last commit's diff.
    public func lastCommitDiff(worktreePath: String) async throws -> String {
        try await git(["show", "--format=", "--patch", "HEAD"], in: worktreePath).standardOutput
    }

    /// Every commit on the branch against its merge base with a base
    /// ref, the whole-branch review.
    public func branchDiff(worktreePath: String, baseRef: String) async throws -> String {
        try await git(["diff", baseRef + "...HEAD"], in: worktreePath).standardOutput
    }

    /// The branch's commits beyond the base ref, newest first, one
    /// line each.
    public func branchCommits(worktreePath: String, baseRef: String) async -> [String] {
        let result = try? await git(
            ["log", "--format=%h %s", baseRef + "..HEAD"],
            in: worktreePath,
            allowFailure: true,
        )
        return (result?.standardOutput ?? "").split(separator: "\n").map(String.init)
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

    /// The worktree's current HEAD commit, nil when unreadable.
    public func headCommit(worktreePath: String) async -> String? {
        let result = try? await git(["rev-parse", "HEAD"], in: worktreePath, allowFailure: true)
        guard let result, result.succeeded else {
            return nil
        }

        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// When the branch last committed, in seconds since 1970.
    public func lastCommitDate(worktreePath: String) async -> Int {
        let result = try? await git(["log", "-1", "--format=%ct"], in: worktreePath, allowFailure: true)
        return Int(result?.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
    }

    /// Fetches and prunes every remote.
    public func fetch(repositoryPath: String) async throws {
        try await git(["fetch", "--all", "--prune"], in: repositoryPath)
    }

    /// Fetches origin and hard-resets the checkout to its default
    /// branch, for main checkouts that should mirror the remote.
    public func fetchAndReset(repositoryPath: String) async throws {
        try await git(["fetch", "origin"], in: repositoryPath)
        try await git(["reset", "--hard", "origin/HEAD"], in: repositoryPath)
    }

    /// Fetches origin and rebases the worktree onto its default
    /// branch, re-signing every commit; failure or conflict aborts
    /// the rebase so the worktree is left exactly as it was.
    public func rebaseSignedOntoOrigin(worktreePath: String) async throws {
        try await git(["fetch", "origin"], in: worktreePath)
        do {
            try await git(["rebase", "--force-rebase", "--gpg-sign", "origin/HEAD"], in: worktreePath)
        } catch {
            try? await git(["rebase", "--abort"], in: worktreePath, allowFailure: true)
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
        try await git(["log", "-1", "--format=%B"], in: worktreePath)
            .standardOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Stages everything and commits it.
    public func commitAll(worktreePath: String, message: String) async throws {
        try await git(["add", "-A"], in: worktreePath)
        try await git(["commit", "-m", message], in: worktreePath)
    }

    /// Pushes the branch, creating its upstream.
    public func push(worktreePath: String, branch: String) async throws {
        try await git(["push", "--set-upstream", "origin", branch], in: worktreePath)
    }

    /// Removes a worktree and deletes its branch; the archive bundle
    /// keeps the commits recoverable. Pruning drops any stale
    /// bookkeeping so the listing never shows a removed worktree.
    public func removeWorktree(repository: Repository, worktreePath: String, branch: String) async throws {
        try await git(["worktree", "remove", "--force", worktreePath], in: repository.path)
        try await git(["worktree", "prune"], in: repository.path)
        try await git(["branch", "-D", branch], in: repository.path)
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
        let argv = ["git"] + Self.hardening + arguments
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

    private let runner: any ProcessRunner
}
