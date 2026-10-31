import Foundation

public extension GitClient {
    /// Puts one tracked path back to what HEAD has, in the index
    /// and the worktree both: every uncommitted change to it goes.
    func restoreFromHead(worktreePath: String, path: String, oldPath: String? = nil) async throws {
        try await git(["checkout", "HEAD", "--", oldPath ?? path], in: worktreePath)
        if oldPath != nil {
            try await git(["rm", "--cached", "--force", "--ignore-unmatch", "--", path], in: worktreePath)
            if FileManager.default.fileExists(atPath: worktreePath + "/" + path) {
                try FileManager.default.removeItem(atPath: worktreePath + "/" + path)
            }
        }
    }
}
