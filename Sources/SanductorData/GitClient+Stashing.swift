import Foundation

extension GitClient {
    /// Restores the exact saved index and worktree, leaving a recoverable stash on conflict.
    func preservingChanges<Value: Sendable>(
        in paths: [String],
        operation: () async throws -> Value,
    ) async throws -> Value {
        var saved = [SavedChanges]()
        let result: Result<Value, any Error>
        do {
            for path in Set(paths).sorted() {
                let status = try await git(["status", "--porcelain"], in: path)
                guard status.standardOutput.isEmpty == false else {
                    continue
                }

                let branch = await currentBranch(worktreePath: path)
                let label = "Sanductor temporary changes " + UUID().uuidString
                let pushed = try await git(
                    ["stash", "push", "--include-untracked", "--message", label], in: path, allowFailure: true,
                )
                let stashes = try await git(["stash", "list", "--format=%H%x00%gs"], in: path).standardOutput
                let commit = stashes.split(separator: "\n")
                    .first { $0.contains(label) }?
                    .split(separator: "\0")
                    .first
                    .map(String.init)
                if let commit {
                    saved.append(SavedChanges(path: path, commit: commit, branch: branch))
                }
                guard pushed.succeeded else {
                    throw CommandError(command: "git stash in " + path, result: pushed)
                }
                guard commit != nil else {
                    throw SessionServiceError("Git could not temporarily stash changes in " + path + ".")
                }
            }
            result = try await .success(operation())
        } catch {
            result = .failure(error)
        }
        var failures = await restoreChanges(saved)
        if failures.isEmpty == false {
            if case let .failure(error) = result {
                failures.insert(error.localizedDescription, at: 0)
            }
            throw SessionServiceError(failures.joined(separator: "\n"))
        }
        return try result.get()
    }

    private struct SavedChanges {
        let path: String
        let commit: String
        let branch: String?
    }

    private func restoreChanges(_ saved: [SavedChanges]) async -> [String] {
        var failures = [String]()
        for entry in saved.reversed() {
            do {
                guard await currentBranch(worktreePath: entry.path) == entry.branch else {
                    throw SessionServiceError("The original branch could not be restored; changes remain in the stash.")
                }

                try await git(["stash", "apply", "--index", entry.commit], in: entry.path)
                let stashes = try await git(["stash", "list", "--format=%H %gd"], in: entry.path).standardOutput
                if let line = stashes.split(separator: "\n").first(where: { $0.hasPrefix(entry.commit + " ") }),
                   let ref = line.split(separator: " ").last
                {
                    try await git(["stash", "drop", String(ref)], in: entry.path)
                }
            } catch {
                failures.append("Changes saved as " + entry.commit + " in " + entry.path
                    + "; resolve any conflicts before recovering missing changes with git stash apply --index "
                    + entry.commit
                    + ": " + error.localizedDescription)
            }
        }
        return failures
    }
}
