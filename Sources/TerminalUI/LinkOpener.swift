import AppKit
import Foundation

// MARK: - UtilityTabTarget

/// The utility tab names modules write to the `utilityTab` storage
/// key. They match `UtilityTab`'s raw values in the app; names
/// survive tab reordering, which silently repointed the integer
/// indices this bus used to carry.
public enum UtilityTabTarget {
    /// The cross-module storage key that switches the utility tab.
    public static let key = "utilityTab"

    /// The embedded browser tab.
    public static let browser = "browser"

    /// The editor tab.
    public static let editor = "editor"

    /// The errors tab.
    public static let errors = "errors"
}

// MARK: - LinkOpener

/// Opens web links: in the embedded Browser tab by default, in the
/// system browser when the command key is held.
public enum LinkOpener {
    /// Routes an address by the command key.
    @preconcurrency
    @MainActor
    public static func open(_ address: String) {
        if NSEvent.modifierFlags.contains(.command) {
            if let url = URL(string: address) {
                NSWorkspace.shared.open(url)
            }
        } else {
            UserDefaults.standard.set(address, forKey: "browserAddress")
            UserDefaults.standard.set(UtilityTabTarget.browser, forKey: UtilityTabTarget.key)
        }
    }
}

// MARK: - FileOpener

/// Opens files: in the Editor tab by default, in an external editor
/// when the command key is held. The external command comes from the
/// `externalEditorCommand` default (space-separated argv), falling
/// back to the system's default application.
public enum FileOpener {
    // MARK: Public

    /// Routes a worktree-relative file by the command key. Paths
    /// that resolve outside the worktree are refused: a hostile
    /// repository could put `../` segments in a diff path.
    @preconcurrency
    @MainActor
    public static func open(relativePath: String, line: Int?, worktreePath: String) {
        guard let absolute = safePath(relativePath: relativePath, worktreePath: worktreePath) else {
            return
        }
        guard NSEvent.modifierFlags.contains(.command) else {
            let defaults = UserDefaults.standard
            defaults.set(relativePath, forKey: "editorFilePath")
            defaults.set(line ?? 0, forKey: "editorFileLine")
            defaults.set(worktreePath, forKey: "editorFileWorktree")
            defaults.set(defaults.integer(forKey: "editorFileRequest") + 1, forKey: "editorFileRequest")
            defaults.set(UtilityTabTarget.editor, forKey: UtilityTabTarget.key)
            return
        }

        let command = UserDefaults.standard.string(forKey: "externalEditorCommand") ?? ""
        let argv = command.split(separator: " ").map(String.init)
        if argv.isEmpty {
            NSWorkspace.shared.open(URL(filePath: absolute))
        } else {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/env")
            process.arguments = argv + [absolute]
            try? process.run()
        }
    }

    // MARK: Private

    /// The resolved path, but only when it stays inside the worktree.
    private static func safePath(relativePath: String, worktreePath: String) -> String? {
        let base = URL(fileURLWithPath: worktreePath).standardizedFileURL.path
        let target = URL(fileURLWithPath: worktreePath + "/" + relativePath).standardizedFileURL.path
        return target == base || target.hasPrefix(base + "/") ? target : nil
    }
}
