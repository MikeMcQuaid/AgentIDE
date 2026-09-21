import AgentIDEDomain
import Foundation

public extension SessionService {
    /// The latest persisted review and human decisions.
    func localReview(worktreePath: String) -> LocalReview? {
        store.load().localReviews[worktreePath]
    }

    /// Saves human feedback outside the shared workspace.
    func saveLocalReview(_ review: LocalReview, worktreePath: String) {
        store.update { $0.localReviews[worktreePath] = review }
    }

    /// Uses the chosen default, otherwise the other agent for the last session.
    func localReviewer(worktreePath: String, defaults: UserDefaults = .standard) -> AgentKind {
        if let name = defaults.string(forKey: AppSettings.reviewAgentKey), let agent = AgentKind(rawValue: name) {
            return agent
        }
        let session = store.load().sessionsByWorktree[worktreePath] ?? ""
        let agent = agentKind(of: session)
            ?? defaults.string(forKey: "agentKind").flatMap(AgentKind.init(rawValue:)) ?? .claudeCode
        return agent == .codexCLI ? .claudeCode : .codexCLI
    }

    /// Detects edits outside the selected diff as well as moved commits.
    func localReviewRevision(worktreePath: String) async throws -> String {
        guard let head = await git.commitHash(of: "HEAD", worktreePath: worktreePath) else {
            throw SessionServiceError("The worktree has no HEAD to review.")
        }

        let changes = try await git.uncommittedDiff(worktreePath: worktreePath)
        return LocalReviewInput.fingerprint(head + "\n" + changes)
    }

    /// Runs the other CLI against a captured diff without a working copy.
    func runLocalReview(
        files: [DiffFile],
        worktreePath: String,
        reviewer: AgentKind,
        instructions: String = LocalReviewInput.instructions,
    ) async throws -> LocalReview {
        try requireSandboxWorkspace(worktreePath)
        let options = AppSettings.reviewOptions(for: reviewer)
        let snapshot = LocalReviewInput.snapshot(files: files)
        guard snapshot.isEmpty == false, snapshot.utf8.count <= LocalReviewInput.byteLimit else {
            throw SessionServiceError("Choose a non-empty diff smaller than 256 KiB for local review.")
        }

        let input = try LocalReviewInput.prompt(instructions: instructions, snapshot: snapshot)

        let revision = try await localReviewRevision(worktreePath: worktreePath)
        await clearQuarantine(for: reviewer)
        guard let executable = Quarantine.homebrewBinaries
            .map({ $0 + "/" + reviewer.rawValue })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else {
            throw SessionServiceError("Install " + reviewer.displayName + " before asking it to review.")
        }

        let directory = paths.agentideDirectory + "/reviews/" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let promptFile = directory + "/prompt.txt"
        let schemaFile = directory + "/schema.json"
        try input.write(toFile: promptFile, atomically: true, encoding: .utf8)
        try LocalReviewInput.schema.write(toFile: schemaFile, atomically: true, encoding: .utf8)
        let adapter = runner(for: reviewer)
        let payload = "export TMPDIR=" + directory.shellQuoted + "; cd " + directory.shellQuoted + " && "
            + adapter.reviewCommand(
                executable: executable, promptFile: promptFile, schemaFile: schemaFile, options: options,
            )
        let result = try await processes.run(
            launcher.command(
                payload: payload,
                initialDirectory: directory,
                sessionID: UUID().uuidString,
                sessionName: "agentide-local-review",
            ),
            workingDirectory: nil,
            environment: [:],
            outputLimit: LocalReviewInput.byteLimit,
        )
        var review = LocalReviewInput.review(
            result: result, files: files, adapter: adapter, revision: revision, input: input,
        )
        review.instructions = instructions
        return review
    }
}
