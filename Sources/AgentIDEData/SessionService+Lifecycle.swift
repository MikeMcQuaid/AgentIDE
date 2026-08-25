import AgentIDEDomain
import Foundation

/// Deleting worktrees. Deletion never touches transcripts in the
/// sandbox home, so every conversation stays readable and resumable
/// from the repository's sessions browser afterwards.
public extension SessionService {
    /// Kills any session, records its resume id, then removes the
    /// worktree, its branch and any symlink an earlier release left
    /// beside it. The recorded session mapping survives, which is
    /// how the conversation stays attributed to the repository.
    func deleteWorktree(item: WorktreeItem) async throws {
        // The conversation is being thrown away deliberately, so its
        // copy goes too rather than lingering in iCloud.
        ConversationBackup(paths: paths).forget(worktree: item.worktree)
        let worktree = item.worktree
        guard worktree.path != worktree.repositoryPath else {
            throw CommandError(
                command: "delete " + worktree.path,
                result: ProcessResult(
                    status: 1,
                    standardOutput: "",
                    standardError: "The main checkout cannot be deleted",
                ),
            )
        }

        let sessionName = item.session?.name
            ?? SessionName.make(repository: worktree.repositoryName, branch: worktree.branch, agent: .claudeCode)
        rememberResumeID(sessionName: sessionName, worktreePath: worktree.path)
        await killSession(name: sessionName)

        let repository = Repository(name: worktree.repositoryName, path: worktree.repositoryPath)
        do {
            try await git.removeWorktree(
                repository: repository,
                worktreePath: worktree.path,
                branch: worktree.branch,
            )
        } catch {
            // Agents create files as the sandbox user (build
            // products, caches) that the host user cannot delete;
            // the removal runs again as their owner, then git
            // forgets the worktree.
            try await removeAsSandboxUser(path: worktree.path)
            try await git.forgetWorktree(repository: repository, branch: worktree.branch)
        }
        removeFriendlySymlink(worktree: worktree)
    }

    /// Deletes a repository's checkout from disk, refusing while the
    /// dashboard's rule (`RepositoryGroup.deletionBlocker`) would:
    /// the rule is re-read here from a fresh reading so a stale
    /// sidebar can never delete work. The checkout goes as the host
    /// user first and as the sandbox user when its files are owned
    /// there, then the repository's empty worktree container and any
    /// symlink in the home directory that pointed at the checkout.
    /// Conversations stay readable: transcripts live in the sandbox
    /// home and the recorded session mapping survives.
    func deleteRepository(_ repository: Repository) async throws {
        let group = await overview().groups.first { $0.repository.path == repository.path }
        let blocker: String? =
            if let group {
                group.deletionBlocker
            } else {
                "the repository is no longer listed"
            }
        if let blocker {
            throw CommandError(
                command: "delete " + repository.path,
                result: ProcessResult(status: 1, standardOutput: "", standardError: "Not deleted: " + blocker),
            )
        }

        do {
            try FileManager.default.removeItem(atPath: repository.path)
        } catch {
            try await removeAsSandboxUser(path: repository.path)
        }
        try? FileManager.default.removeItem(atPath: worktreeContainer(repository: repository))
        let home = FileManager.default.homeDirectoryForCurrentUser
        for entry in (try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? [] {
            let link = home.appending(path: entry).path
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: link)) == repository.path {
                try? FileManager.default.removeItem(atPath: link)
            }
        }
    }

    /// Adds the worktree a new session works in, under the
    /// repository's own directory.
    func createWorktreePath(repository: Repository, branch: String) async throws -> String {
        let path = worktreeContainer(repository: repository) + "/" + branch.replacing("/", with: "-")
        await progress("Running `git worktree add " + path + "`")
        try await git.createWorktree(repository: repository, branch: branch, at: path)
        await progress("Worktree ready at `" + path + "`")
        return path
    }

    /// Adds a detached worktree, letting `gh pr checkout` create the
    /// branch afterwards.
    func createDetachedWorktreePath(repository: Repository, name: String) async throws -> String {
        let path = worktreeContainer(repository: repository) + "/" + name
        try await git.addDetachedWorktree(repository: repository, at: path)
        return path
    }

    /// Fetches and prunes the repository's remotes.
    func fetch(repository: Repository) async throws {
        try await git.fetch(repositoryPath: repository.path)
    }

    /// A tracked file's committed content; see `GitClient`.
    func trackedFile(worktreePath: String, path: String) async -> String? {
        await git.trackedFile(worktreePath: worktreePath, path: path)
    }

    /// Removes the symlink an earlier release kept beside a
    /// uuid-layout worktree; the canonical path is what git knows,
    /// so this is cosmetic cleanup of the old layout.
    internal func removeFriendlySymlink(worktree: Worktree) {
        let link = paths.friendlyWorktreesDirectory + "/" + worktree.repositoryName
            + "/" + worktree.branch.replacing("/", with: "-")
        try? FileManager.default.removeItem(atPath: link)
    }

    /// Why a merge-safe cleanup refused a worktree, so the caller can
    /// name what a forced deletion would destroy.
    enum CleanupRefusal: Equatable, Sendable {
        /// Uncommitted changes would be lost.
        case dirty
        /// Commits not on the base branch would be lost.
        case unmerged
    }

    /// The merge-safe cleanup of a real worktree: refused outright
    /// when the worktree is dirty or its branch has commits the base
    /// branch lacks, so nothing this path does can lose work; the
    /// force delete is a separate, confirmed action. Returns the
    /// refusal, nil when the worktree was removed.
    func cleanUpMergedWorktree(item: WorktreeItem, baseRef: String) async throws -> CleanupRefusal? {
        // A merged worktree is about to go; its conversation copy is
        // dropped only once the removal itself succeeds, below.
        let backup = ConversationBackup(paths: paths)
        let worktree = item.worktree
        guard await git.isDirty(worktreePath: worktree.path) == false else {
            return .dirty
        }
        guard await git.isMerged(worktreePath: worktree.path, branch: worktree.branch, into: baseRef) else {
            return .unmerged
        }

        // Merge-safe git as well as merge-safe checks: `git worktree
        // remove` without `--force` and `git branch -d` refuse dirty
        // or unmerged work themselves, so a wrong or raced check
        // above cannot destroy anything.
        let repository = Repository(name: worktree.repositoryName, path: worktree.repositoryPath)
        let sessionName = item.session?.name
            ?? SessionName.make(repository: worktree.repositoryName, branch: worktree.branch, agent: .claudeCode)
        rememberResumeID(sessionName: sessionName, worktreePath: worktree.path)
        await killSession(name: sessionName)
        try await git.removeMergedWorktree(
            repository: repository,
            worktreePath: worktree.path,
            branch: worktree.branch,
        )
        removeFriendlySymlink(worktree: worktree)
        backup.forget(worktree: worktree)
        return nil
    }

    /// Deletes a path as the sandbox user through the launcher, for
    /// files the host user does not own.
    private func removeAsSandboxUser(path: String) async throws {
        let launcher = SandvaultLauncher(hostUser: paths.hostUser)
        let command = launcher.command(
            payload: "rm -rf " + path.shellQuoted,
            initialDirectory: launcher.sharedWorkspace,
            sessionID: UUID().uuidString,
            sessionName: "agentide-delete",
        )
        let result = try await processes.run(command, workingDirectory: nil, environment: [:])
        guard result.succeeded, FileManager.default.fileExists(atPath: path) == false else {
            throw CommandError(command: "rm -rf " + path, result: result)
        }
    }

    /// Every conversation attributable to the repository, whichever
    /// worktree it ran in, including worktrees that no longer exist.
    /// Newest first.
    func repositorySessions(
        for repository: Repository,
    ) async -> [(session: TranscriptSession, worktreePath: String)] {
        var candidates = [repository.path]
        var known = Set(candidates)
        let worktrees = await (try? git.worktrees(of: repository)) ?? []
        let slug = SessionName.slug(repository.name)
        let recorded = store.load()
            .sessionsByWorktree
            .filter { _, sessionName in SessionName.repositorySlug(of: sessionName) == slug }
            .map(\.key)
        for path in worktrees.map(\.path) + recorded.sorted() where known.insert(path).inserted {
            candidates.append(path)
        }
        let discovered = transcriptWorktreePaths(under: worktreeContainers(of: candidates))
        for path in discovered where known.insert(path).inserted {
            candidates.append(path)
        }

        var seen = Set<String>()
        var results = [(session: TranscriptSession, worktreePath: String)]()
        for path in candidates {
            let sessions = sessionsInDirectories(of: path, liveSession: nil)
            for session in sessions where seen.insert(session.id).inserted {
                results.append((session, path))
            }
        }
        return results.sorted { $0.session.modifiedAt > $1.session.modifiedAt }
    }

    // MARK: Internal

    /// The `worktrees/<repository>` directories the paths live
    /// under (an older release's `worktrees/<uuid>` ones included):
    /// a repository's worktrees share their container, so the
    /// containers attribute conversations to the repository.
    internal func worktreeContainers(of worktreePaths: [String]) -> [String] {
        let prefix = paths.worktreesDirectory + "/"
        var containers = [String]()
        for path in worktreePaths where path.hasPrefix(prefix) {
            guard let group = path.dropFirst(prefix.count).split(separator: "/").first else {
                continue
            }

            let container = prefix + group
            if containers.contains(container) == false {
                containers.append(container)
            }
        }
        return containers
    }

    /// Worktree paths reconstructed from transcript directory names
    /// under the containers, so conversations survive worktrees that
    /// were deleted without ever being recorded. Directory names
    /// encode the working directory, so a name extending a
    /// container's encoding locates a conversation inside it.
    internal func transcriptWorktreePaths(under containers: [String]) -> [String] {
        var found = [String]()
        for runner in runners where runner.scopesTranscriptsByWorkingDirectory {
            for container in containers {
                guard let encoded = runner.transcriptDirectory(
                    workingDirectory: container,
                    sandboxHome: paths.sandboxHome,
                ) else {
                    continue
                }

                let root = URL(filePath: encoded).deletingLastPathComponent().path
                let prefix = URL(filePath: encoded).lastPathComponent + "-"
                let entries = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
                for entry in entries.sorted() where entry.hasPrefix(prefix) {
                    found.append(container + "/" + entry.dropFirst(prefix.count))
                }
            }
        }
        return found
    }
}
