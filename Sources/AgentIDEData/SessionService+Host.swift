import AgentIDEDomain
import Foundation

/// Directories of your own, listed under a repository: a shell, an
/// editor and a diff for somewhere on the Mac, with no agent and no
/// worktree lifecycle. Nothing here ever reaches the sandbox: the
/// sandbox user may well be able to read `/opt/homebrew`, but
/// AgentIDE must never give it a reason to write to one.
public extension SessionService {
    /// The home-directory folders macOS guards, which this app has
    /// no business reading: a stat inside one asks the user for
    /// permission, and the answer is asked for again next time.
    static var guardedFolders: Set<String> {
        ["Documents", "Desktop", "Downloads", "Movies", "Music", "Pictures"]
    }

    /// The storage-bus key naming the selected row, which the
    /// sidebar writes; the only directory of your own worth reading
    /// from disk is the one in front of you.
    static var selectedWorktreeKey: String {
        "selectedWorktreePath"
    }

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

    /// The repository's listed directories, as rows.
    ///
    /// Only the selected one is read from disk; the rest are drawn
    /// from what it last said. A directory of your own can be
    /// anywhere on the Mac, and macOS guards Documents, Desktop,
    /// Downloads and every network volume: a poll that stats one of
    /// those asks the user for permission, and asks again on the
    /// next poll, for a row nobody was looking at. Nothing here can
    /// know which paths are guarded, so nothing here touches a path
    /// the user is not looking at.
    internal func hostItems(of repository: Repository, metadata: AppMetadata) async -> [WorktreeItem] {
        let listed = metadata.hostDirectories[repository.path] ?? []
        let selected = UserDefaults.standard.string(forKey: Self.selectedWorktreeKey)
        var items = [WorktreeItem]()
        for path in listed {
            let facts = path == selected ? await readHostFacts(of: path) : hostFacts.facts(of: path)
            guard facts?.exists != false else {
                continue
            }

            items.append(WorktreeItem(
                worktree: Worktree(
                    repositoryName: repository.name,
                    repositoryPath: repository.path,
                    branch: facts?.branch ?? "",
                    path: path,
                    isHostDirectory: true,
                ),
                session: nil,
                isDirty: facts?.isDirty ?? false,
                aheadOfUpstream: facts?.aheadOfUpstream,
                hasUnread: false,
            ))
        }
        return items
    }

    /// Reads one directory of your own and remembers what it said,
    /// so its row keeps painting while nothing touches it again.
    private func readHostFacts(of path: String) async -> HostFacts {
        guard FileManager.default.fileExists(atPath: path) else {
            let gone = HostFacts(exists: false, branch: "", isDirty: false, aheadOfUpstream: nil)
            hostFacts.remember(gone, of: path)
            return gone
        }

        let branch = await git.currentBranch(worktreePath: path) ?? ""
        let isDirty = await git.isDirty(worktreePath: path)
        let ahead = await git.aheadOfUpstream(worktreePath: path)
        let facts = HostFacts(exists: true, branch: branch, isDirty: isDirty, aheadOfUpstream: ahead)
        hostFacts.remember(facts, of: path)
        return facts
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
