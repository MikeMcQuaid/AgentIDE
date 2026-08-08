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

    /// Creates a worktree with a new branch based on `HEAD`.
    public func createWorktree(repository: Repository, branch: String, at path: String) async throws {
        try await git(["worktree", "add", "-b", branch, path, "HEAD"], in: repository.path)
    }

    /// Adds a worktree for an existing branch, used by undelete.
    public func addWorktree(repository: Repository, branch: String, at path: String) async throws {
        try await git(["worktree", "add", path, branch], in: repository.path)
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

    /// Writes a bundle containing the branch.
    public func bundle(worktreePath: String, branch: String, to file: String) async throws {
        try await git(["bundle", "create", file, branch], in: worktreePath)
    }

    /// Untracked and modified paths, used when archiving.
    public func looseFiles(worktreePath: String) async -> [String] {
        let output = try? await git(
            ["ls-files", "--others", "--modified", "--exclude-standard"],
            in: worktreePath,
        ).standardOutput
        return (output ?? "").split(separator: "\n").map(String.init)
    }

    /// Removes a worktree and deletes its branch; the archive bundle
    /// keeps the commits recoverable.
    public func removeWorktree(repository: Repository, worktreePath: String, branch: String) async throws {
        try await git(["worktree", "remove", "--force", worktreePath], in: repository.path)
        try await git(["branch", "-D", branch], in: repository.path)
    }

    /// Recreates a branch from an archive bundle.
    public func fetchBranch(repository: Repository, fromBundle bundle: String, branch: String) async throws {
        try await git(["fetch", bundle, branch + ":" + branch], in: repository.path)
    }

    // MARK: Private

    /// Config a compromised repository could abuse, forced off.
    private static let hardening = [
        "-c", "core.fsmonitor=",
        "-c", "core.sshCommand=",
        "-c", "core.hooksPath=/dev/null",
        "-c", "core.pager=cat",
        "-c", "protocol.ext.allow=never",
    ]

    private let runner: any ProcessRunner

    @discardableResult
    private func git(
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
}
