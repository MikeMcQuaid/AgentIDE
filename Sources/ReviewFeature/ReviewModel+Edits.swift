import AgentIDEDomain
import Foundation

/// Putting back or throwing away the working files the uncommitted
/// diff shows. Split from the model body for length.
extension ReviewModel {
    /// Puts a tracked working file back to what HEAD has, staged
    /// changes included, then reloads so the diff no longer shows
    /// it. False means git refused and the status says why.
    @discardableResult
    func resetFile(_ file: DiffFile) async -> Bool {
        do {
            try await git.restoreFromHead(worktreePath: worktreePath, path: file.path)
        } catch {
            status = "Resetting " + file.path + " failed: " + error.localizedDescription
            return false
        }
        await reload()
        return true
    }

    /// Deletes a working file the uncommitted diff shows, so the
    /// diff then shows the deletion (or, for a file never committed,
    /// nothing at all). False means it could not be removed.
    @discardableResult
    func deleteFile(_ file: DiffFile) async -> Bool {
        do {
            try FileManager.default.removeItem(atPath: worktreePath + "/" + file.path)
        } catch {
            status = "Deleting " + file.path + " failed: " + error.localizedDescription
            return false
        }
        await reload()
        return true
    }
}
