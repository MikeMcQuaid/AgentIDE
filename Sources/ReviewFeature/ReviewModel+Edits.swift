import AgentIDEDomain
import Foundation

/// Editing the working files the uncommitted diff shows, in place.
/// Split from the model body for length.
extension ReviewModel {
    /// Replaces one line of a working file with the typed text,
    /// which may be several lines, then reloads so the diff shows
    /// the edit as it stands. Uncommitted scope only: the line is
    /// named by its new-side number, which is what the working file
    /// holds, and a removed line has no such number to edit. False
    /// means the file could not be written and the status says why.
    @discardableResult
    func replaceLine(in file: DiffFile, newLineNumber: Int, with text: String) async -> Bool {
        let path = worktreePath + "/" + file.path
        do {
            let contents = try String(contentsOfFile: path, encoding: .utf8)
            let endsWithNewline = contents.hasSuffix("\n")
            var lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if endsWithNewline {
                lines.removeLast()
            }
            guard lines.indices.contains(newLineNumber - 1) else {
                status = "Line " + String(newLineNumber) + " is no longer in " + file.path + "."
                return false
            }

            lines.replaceSubrange((newLineNumber - 1) ... (newLineNumber - 1), with: [text])
            try (lines.joined(separator: "\n") + (endsWithNewline ? "\n" : ""))
                .write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            status = "Editing " + file.path + " failed: " + error.localizedDescription
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
