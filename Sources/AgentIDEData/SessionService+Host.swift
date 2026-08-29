import AgentIDEDomain
import Foundation

/// Directories of your own, listed under a repository: a shell, an
/// editor and a diff for somewhere on the Mac, with no agent and no
/// worktree lifecycle. Nothing here ever reaches the sandbox: the
/// sandbox user may well be able to read `/opt/homebrew`, but
/// AgentIDE must never give it a reason to write to one.
public extension SessionService {
    /// Lists a directory of your own under a repository.
    func addHostDirectory(_ path: String, to repository: Repository) {
        var listed = store.load().hostDirectories[repository.path] ?? []
        guard listed.contains(path) == false else {
            return
        }

        listed.append(path)
        store.update { $0.hostDirectories[repository.path] = listed.sorted() }
    }

    /// Stops listing one. Nothing on disk is touched: these are not
    /// AgentIDE's to delete.
    func forgetHostDirectory(_ path: String, from repositoryPath: String) {
        store.update { metadata in
            metadata.hostDirectories[repositoryPath]?.removeAll { $0 == path }
            if metadata.hostDirectories[repositoryPath]?.isEmpty == true {
                metadata.hostDirectories[repositoryPath] = nil
            }
        }
    }

    /// Publishes the listed directories where the `agentide`
    /// command can read them, so `agentide .` in one of them
    /// selects it the way it selects a worktree. One path per line:
    /// a path can hold anything a `key=value` line cannot.
    func publishHostDirectories(_ paths: [String]) {
        try? FileManager.default.createDirectory(
            atPath: self.paths.agentideDirectory,
            withIntermediateDirectories: true,
        )
        try? (paths.sorted().joined(separator: "\n") + "\n").write(
            toFile: self.paths.agentideDirectory + "/host-directories",
            atomically: true,
            encoding: .utf8,
        )
    }

    /// Checks out a repository's default branch where it is checked
    /// out and brings it level with origin.
    func checkoutAndPullDefault(worktreePath: String, repository: Repository) async throws {
        guard let baseRef = await git.defaultBaseRef(of: repository) else {
            throw CommandError(
                command: "checkout default in " + worktreePath,
                result: ProcessResult(status: 1, standardOutput: "", standardError: "No default branch"),
            )
        }

        try await git.checkoutAndPullDefault(
            worktreePath: worktreePath,
            branch: Self.branchName(fromBaseRef: baseRef),
        )
    }

    // MARK: Internal

    /// Refuses a path outside the shared workspace. Every launch
    /// passes through one function, so this is the one place worth
    /// being sure: a directory of your own is not the sandbox's to
    /// work in, whether or not it could read it.
    internal func requireSandboxWorkspace(_ path: String) throws {
        guard path.hasPrefix(paths.sharedWorkspace + "/") == false else {
            return
        }

        throw CommandError(
            command: "launch in " + path,
            result: ProcessResult(
                status: 1,
                standardOutput: "",
                standardError: "Only worktrees of " + paths.sharedWorkspace + " run agents",
            ),
        )
    }

    /// The repository's listed directories, as rows: their branch is
    /// shown for orientation, and a missing one is dropped rather
    /// than shown as a row that opens nothing.
    internal func hostItems(of repository: Repository, metadata: AppMetadata) async -> [WorktreeItem] {
        var items = [WorktreeItem]()
        let listed = (metadata.hostDirectories[repository.path] ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }
        let branches = await withTaskGroup(of: (String, String).self) { tasks in
            for path in listed {
                tasks.addTask { await (path, self.git.currentBranch(worktreePath: path) ?? "") }
            }
            var collected = [String: String]()
            for await (path, branch) in tasks {
                collected[path] = branch
            }
            return collected
        }
        for path in listed {
            let branch = branches[path] ?? ""
            await items.append(WorktreeItem(
                worktree: Worktree(
                    repositoryName: repository.name,
                    repositoryPath: repository.path,
                    branch: branch,
                    path: path,
                    isHostDirectory: true,
                ),
                session: nil,
                isDirty: git.isDirty(worktreePath: path),
                aheadOfUpstream: git.aheadOfUpstream(worktreePath: path),
                hasUnread: false,
            ))
        }
        return items
    }

    /// The local branches a worktree could switch to: everything
    /// but the branches some worktree of the repository, this one
    /// included, already holds — git would refuse those anyway.
    func availableBranches(worktree: Worktree) async -> [String] {
        let repository = Repository(name: worktree.repositoryName, path: worktree.repositoryPath)
        let held = await (try? git.worktrees(of: repository))?.map(\.branch) ?? [worktree.branch]
        let all = await git.branches(worktreePath: worktree.path)
        return all.filter { held.contains($0) == false }
    }

    /// Checks out another local branch in place; git reports a
    /// conflicting dirty file rather than losing it.
    func switchBranch(_ branch: String, worktree: Worktree) async throws {
        try await git.checkout(branch: branch, worktreePath: worktree.path)
    }
}
