import Foundation

/// Branch inspection and the repository-local exclude file, split
/// from the client body for length.
public extension GitClient {
    /// The branch actually checked out in a worktree, nil when
    /// detached or unreadable; agents sometimes switch away from the
    /// branch the worktree was created for.
    func currentBranch(worktreePath: String) async -> String? {
        let name = try? await git(["rev-parse", "--abbrev-ref", "HEAD"], in: worktreePath)
            .standardOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, name.isEmpty == false, name != "HEAD" else {
            return nil
        }

        return name
    }

    /// Hides a path from git status for this clone only: the exclude
    /// file lives in the common git directory, shared by every
    /// worktree, and nothing tracked changes.
    func excludeLocally(pattern: String, worktreePath: String) async throws {
        let common = try await git(["rev-parse", "--git-common-dir"], in: worktreePath)
            .standardOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let directory = (common.hasPrefix("/") ? common : worktreePath + "/" + common) + "/info"
        let file = directory + "/exclude"
        let existing = (try? String(contentsOfFile: file, encoding: .utf8)) ?? ""
        guard existing.split(separator: "\n").contains(Substring(pattern)) == false else {
            return
        }

        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
        try (existing + separator + pattern + "\n").write(toFile: file, atomically: true, encoding: .utf8)
    }
}
