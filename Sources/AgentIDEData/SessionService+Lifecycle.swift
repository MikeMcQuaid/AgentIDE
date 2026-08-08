import AgentIDEDomain
import Foundation

/// Archiving, deleting and restoring worktrees. The archive lives
/// outside the guest-writable workspace so agents cannot tamper with
/// recovery state.
extension SessionService {
    // MARK: Public

    /// Archives a worktree's branch, loose files, transcript and
    /// prompt, then deletes the worktree and branch.
    public func archiveAndDelete(item: WorktreeItem) async throws -> ArchiveMetadata {
        let worktree = item.worktree
        let sessionName = item.session?.name
            ?? SessionName.make(repository: worktree.repositoryName, branch: worktree.branch, agent: .claudeCode)
        rememberResumeID(sessionName: sessionName, worktreePath: worktree.path)

        let identifier = UUID().uuidString.lowercased()
        let archiveDirectory = paths.archivesDirectory + "/" + identifier
        try FileManager.default.createDirectory(atPath: archiveDirectory, withIntermediateDirectories: true)
        try await git.bundle(
            worktreePath: worktree.path,
            branch: worktree.branch,
            to: archiveDirectory + "/branch.bundle",
        )
        try await archiveLooseFiles(worktree: worktree, to: archiveDirectory)
        copyIfPresent(paths.promptsDirectory + "/" + sessionName + ".md", into: archiveDirectory)
        copyIfPresent(paths.eventsDirectory + "/" + sessionName + ".jsonl", into: archiveDirectory)

        let metadata = ArchiveMetadata(
            id: identifier,
            repositoryName: worktree.repositoryName,
            repositoryPath: worktree.repositoryPath,
            branch: worktree.branch,
            worktreePath: worktree.path,
            sessionName: sessionName,
            resumeID: store.load().resumeIDs[sessionName],
            archivedAt: Date(),
        )
        try metadataJSON(metadata).write(
            toFile: archiveDirectory + "/metadata.json",
            atomically: true,
            encoding: .utf8,
        )

        try? await tmux.killSession(name: sessionName)
        let repository = Repository(name: worktree.repositoryName, path: worktree.repositoryPath)
        try await git.removeWorktree(repository: repository, worktreePath: worktree.path, branch: worktree.branch)
        removeFriendlySymlink(repository: repository, branch: worktree.branch)

        var app = store.load()
        app.archives.append(metadata)
        store.save(app)
        return metadata
    }

    /// Restores an archived worktree at its original canonical path
    /// so cwd-keyed conversation state lines up.
    public func undelete(archive: ArchiveMetadata) async throws {
        let repository = Repository(name: archive.repositoryName, path: archive.repositoryPath)
        let archiveDirectory = paths.archivesDirectory + "/" + archive.id
        if await git.branchExists(repository: repository, branch: archive.branch) == false {
            try await git.fetchBranch(
                repository: repository,
                fromBundle: archiveDirectory + "/branch.bundle",
                branch: archive.branch,
            )
        }
        try await git.addWorktree(repository: repository, branch: archive.branch, at: archive.worktreePath)
        try? await restoreLooseFiles(from: archiveDirectory, to: archive.worktreePath)
        addFriendlySymlink(repository: repository, branch: archive.branch, worktreePath: archive.worktreePath)

        var app = store.load()
        app.archives.removeAll { $0.id == archive.id }
        if let resumeID = archive.resumeID {
            app.resumeIDs[archive.sessionName] = resumeID
        }
        store.save(app)
    }

    // MARK: Internal

    func removeFriendlySymlink(repository: Repository, branch: String) {
        let link = paths.friendlyWorktreesDirectory + "/" + repository.name
            + "/" + branch.replacing("/", with: "-")
        try? FileManager.default.removeItem(atPath: link)
    }

    // MARK: Private

    private func copyIfPresent(_ source: String, into directory: String) {
        guard FileManager.default.fileExists(atPath: source) else {
            return
        }

        let destination = directory + "/" + URL(fileURLWithPath: source).lastPathComponent
        try? FileManager.default.copyItem(atPath: source, toPath: destination)
    }

    private func archiveLooseFiles(worktree: Worktree, to archiveDirectory: String) async throws {
        let files = await git.looseFiles(worktreePath: worktree.path)
        guard files.isEmpty == false else {
            return
        }

        let listFile = archiveDirectory + "/loose-files.txt"
        try files.joined(separator: "\n").write(toFile: listFile, atomically: true, encoding: .utf8)
        _ = try await runTool(
            ["tar", "-czf", archiveDirectory + "/loose.tar.gz", "-C", worktree.path, "-T", listFile],
        )
    }

    private func restoreLooseFiles(from archiveDirectory: String, to worktreePath: String) async throws {
        let tarball = archiveDirectory + "/loose.tar.gz"
        guard FileManager.default.fileExists(atPath: tarball) else {
            return
        }

        _ = try await runTool(["tar", "-xzf", tarball, "-C", worktreePath])
    }

    private func runTool(_ arguments: [String]) async throws -> ProcessResult {
        let runner = FoundationProcessRunner()
        let result = try await runner.run(arguments, workingDirectory: nil, environment: [:])
        guard result.succeeded else {
            throw CommandError(command: arguments.joined(separator: " "), result: result)
        }

        return result
    }

    private func metadataJSON(_ metadata: ArchiveMetadata) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(metadata)
        return String(bytes: data, encoding: .utf8) ?? "{}"
    }
}
