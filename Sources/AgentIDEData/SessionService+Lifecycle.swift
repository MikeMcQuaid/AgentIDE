import AgentIDEDomain
import Foundation

/// Deleting worktrees. Deletion never touches transcripts in the
/// sandbox home, so every conversation stays readable and resumable
/// from the repository's sessions browser afterwards.
public extension SessionService {
    /// Kills any session, records its resume id, then removes the
    /// worktree, its branch and its friendly symlink. The recorded
    /// session mapping survives, which is how the conversation stays
    /// attributed to the repository.
    func deleteWorktree(item: WorktreeItem) async throws {
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
        try? await tmux.killSession(name: sessionName)

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
        let link = paths.friendlyWorktreesDirectory + "/" + worktree.repositoryName
            + "/" + worktree.branch.replacing("/", with: "-")
        try? FileManager.default.removeItem(atPath: link)
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

    /// The `worktrees/<uuid>` directories the paths live under: every
    /// worktree of a repository shares its uuid container, so the
    /// containers attribute conversations to the repository.
    internal func worktreeContainers(of worktreePaths: [String]) -> [String] {
        let prefix = paths.worktreesDirectory + "/"
        var containers = [String]()
        for path in worktreePaths where path.hasPrefix(prefix) {
            guard let uuid = path.dropFirst(prefix.count).split(separator: "/").first else {
                continue
            }

            let container = prefix + uuid
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
