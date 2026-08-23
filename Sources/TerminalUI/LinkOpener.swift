import AppKit
import Foundation
import SwiftUI

// MARK: - UtilityTabTarget

/// The utility tab names modules write to the `utilityTab` storage
/// key. They match `UtilityTab`'s raw values in the app; names
/// survive tab reordering, which silently repointed the integer
/// indices this bus used to carry.
public enum UtilityTabTarget {
    /// The cross-module storage key that switches the utility tab.
    public static let key = "utilityTab"

    /// The key that shows the utility pane, for the panes that must
    /// be seen whether or not it was open.
    public static let visibilityKey = "showsUtilityPane"

    /// The embedded browser tab.
    public static let browser = "browser"

    /// The address the browser is being asked for, and the count of
    /// times one has been asked for. The count is what a pane
    /// watches: asking twice for the same page writes the same
    /// string, which publishes no change, so a link clicked after
    /// the browser had wandered off elsewhere did nothing at all.
    public static let addressKey = "browserAddress"

    /// The count of address requests, which is what changes when the
    /// same page is asked for twice.
    public static let requestKey = "browserRequest"

    /// The editor tab.
    public static let editor = "editor"

    /// The errors tab.
    public static let errors = "errors"
}

// MARK: - LinkOpener

/// Opens web links: in the embedded Browser tab by default, in the
/// system browser when the command key is held.
public enum LinkOpener {
    // MARK: Public

    /// The action every in-app link takes, installed at the window's
    /// root: web links route through `open`, so a link in a
    /// conversation or pull request lands in the embedded browser,
    /// and anything else is refused with a message. Handing those to
    /// the system opener produced an unhelpful "error -50" dialog
    /// for relative and schemeless links.
    public static let action = OpenURLAction { url in
        MainActor.assumeIsolated {
            guard isWeb(url) else {
                ErrorLog.shared.report("Not a web link, so not opened: " + url.absoluteString)
                return .discarded
            }

            open(url.absoluteString)
            return .handled
        }
    }

    /// Routes an address by the command key; only web links reach
    /// the system browser, for the same reason as `action`.
    @preconcurrency
    @MainActor
    public static func open(_ address: String) {
        if NSEvent.modifierFlags.contains(.command) {
            if let url = URL(string: address), isWeb(url) {
                NSWorkspace.shared.open(url)
            }
        } else {
            let defaults = UserDefaults.standard
            defaults.set(address, forKey: UtilityTabTarget.addressKey)
            defaults.set(defaults.integer(forKey: UtilityTabTarget.requestKey) + 1, forKey: UtilityTabTarget.requestKey)
            defaults.set(UtilityTabTarget.browser, forKey: UtilityTabTarget.key)
        }
    }

    /// Opens a link only when it is a web link, ignoring anything
    /// else so a bare file path a terminal detected under the cursor
    /// never reaches the system opener, which handed it to Finder for
    /// a "-50" dialog. Returns whether it opened.
    @discardableResult
    @preconcurrency
    @MainActor
    public static func openWeb(_ address: String) -> Bool {
        guard let url = URL(string: address), isWeb(url) else {
            return false
        }

        open(address)
        return true
    }

    // MARK: Private

    /// Whether a link has a web scheme and a host, the only shape
    /// either browser can open.
    private static func isWeb(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host() != nil
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
