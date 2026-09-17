import AgentIDEDomain
import Foundation

/// Reading the `.editorconfig` files that govern a file, which is
/// the one part of the format that touches disk; the rules for
/// merging them are the Domain's.
public extension SessionService {
    /// What the file's configuration chain says about editing it.
    /// The walk climbs from the file's own directory to the
    /// worktree root, stopping early at a `root = true` file: the
    /// worktree is the project's boundary, and reading above it
    /// would take settings from whatever else shares the workspace.
    /// A file outside the worktree is governed by nothing inside it.
    /// `@concurrent`, since reading a handful of small files is
    /// blocking work that must not sit on the main actor.
    @concurrent
    func editorConfigSettings(worktreePath: String, filePath: String) async -> EditorConfigSettings {
        // Compared as given: Foundation's standardising drops
        // `/private` from only the part of a path that exists, so a
        // worktree under a temporary directory standardised to one
        // spelling and a file yet to be written in it to another,
        // and every such file read as outside its worktree.
        let root = worktreePath
        var directory = URL(fileURLWithPath: filePath).deletingLastPathComponent().path
        guard directory == root || directory.hasPrefix(root + "/") else {
            return EditorConfigSettings()
        }

        var files = [EditorConfigFile]()
        while true {
            let path = directory + "/" + EditorConfigFile.name
            if let text = try? String(contentsOfFile: path, encoding: .utf8) {
                let file = EditorConfigFile.parse(text, directory: directory)
                files.append(file)
                if file.isRoot {
                    break
                }
            }
            guard directory != root else {
                break
            }

            directory = URL(fileURLWithPath: directory).deletingLastPathComponent().path
        }
        return EditorConfig.settings(forPath: filePath, files: files)
    }
}
