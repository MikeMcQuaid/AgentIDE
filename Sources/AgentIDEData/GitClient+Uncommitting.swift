import Foundation

public extension GitClient {
    /// Amends only the reviewed commit, preserving staged and
    /// working changes and leaving excluded changes uncommitted.
    func amend(
        worktreePath: String,
        excluding paths: [String],
        message: String,
        expectedHead: String,
    ) async throws {
        let scratch = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("agentide-amend-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let environment = ["GIT_INDEX_FILE": scratch.appendingPathComponent("index").path]
        try await git(["read-tree", expectedHead], in: worktreePath, environment: environment)
        if paths.isEmpty == false {
            let parent = try await git(["show", "--no-patch", "--format=%P", expectedHead], in: worktreePath)
                .standardOutput
                .split(whereSeparator: \.isWhitespace)
                .first
                .map(String.init)
            let source: String =
                if let parent {
                    parent
                } else {
                    try await git(["hash-object", "-w", "-t", "tree", "/dev/null"], in: worktreePath)
                        .standardOutput
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            try await git(
                ["--literal-pathspecs", "restore", "--staged", "--source=" + source, "--"]
                    + excludingRenames(paths, commit: expectedHead, worktreePath: worktreePath),
                in: worktreePath,
                environment: environment,
            )
        }
        guard await commitHash(of: "HEAD", worktreePath: worktreePath) == expectedHead else {
            throw SessionServiceError("The last commit changed. Refresh the review before amending it.")
        }

        try await git(["commit", "--amend", "-m", message], in: worktreePath, environment: environment)
    }

    private func excludingRenames(_ paths: [String], commit: String, worktreePath: String) async throws -> [String] {
        var paths = paths
        // Rename records are NUL-separated status, old path, new path.
        var renames = try await git(
            ["diff-tree", "--root", "--no-commit-id", "-r", "-M", "--diff-filter=R", "--name-status", "-z", commit],
            in: worktreePath,
        )
        .standardOutput
        .split(separator: "\0")
        .map(String.init)
        .makeIterator()
        while renames.next() != nil, let old = renames.next(), let new = renames.next() {
            if paths.contains(new) {
                paths.append(old)
            }
        }
        return paths
    }
}
