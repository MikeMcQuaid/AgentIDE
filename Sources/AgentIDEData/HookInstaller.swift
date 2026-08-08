import Foundation

/// Installs AgentIDE's hook script and Claude Code hook entries into
/// the sandvault user template, alongside any existing third-party
/// notifier hooks rather than replacing them.
public struct HookInstaller: Sendable {
    // MARK: Lifecycle

    /// Creates an installer for a workspace.
    public init(paths: WorkspacePaths) {
        self.paths = paths
    }

    // MARK: Public

    /// The events the hook reports, covering completion, permission
    /// requests and lifecycle for the dashboard.
    public static let events = [
        "UserPromptSubmit", "Stop", "StopFailure", "PostToolUse",
        "PostToolUseFailure", "PermissionRequest", "SessionStart", "SessionEnd",
    ]

    /// Ensures the agentide directories, the hook script and the
    /// settings template entries all exist. Idempotent.
    public func ensureInstalled() throws {
        let manager = FileManager.default
        for directory in [paths.eventsDirectory, paths.promptsDirectory, paths.friendlyWorktreesDirectory] {
            try manager.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }
        try installScript()
        try installSettingsEntries()
    }

    // MARK: Private

    private let paths: WorkspacePaths

    private var scriptPath: String {
        paths.userTemplateDirectory + "/.claude/agentide-notify.sh"
    }

    private var settingsPath: String {
        paths.userTemplateDirectory + "/.claude/settings.json"
    }

    private var scriptContent: String {
        """
        #!/bin/sh
        session="${AGENTIDE_SESSION:-${SV_SESSION_ID:-}}"
        [ -n "$session" ] || exit 0
        directory="${SHARED_WORKSPACE:-\(paths.sharedWorkspace)}/agentide/events"
        mkdir -p "$directory"
        printf '{"event":"%s","date":"%s"}\\n' "$1" "$(date -u +%FT%TZ)" >> "$directory/$session.jsonl"
        """
    }

    private func installScript() throws {
        try FileManager.default.createDirectory(
            atPath: URL(fileURLWithPath: scriptPath).deletingLastPathComponent().path,
            withIntermediateDirectories: true,
        )
        try scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
    }

    private func installSettingsEntries() throws {
        let url = URL(fileURLWithPath: settingsPath)
        let existingData = try? Data(contentsOf: url)
        let existing = existingData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        var settings = existing ?? [:]
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in Self.events {
            let command = "[ -x \(scriptPath) ] && \(scriptPath) \(event) || true"
            var entries = hooks[event] as? [[String: Any]] ?? []
            let alreadyInstalled = entries.contains { entry in
                let nested = entry["hooks"] as? [[String: Any]] ?? []
                return nested.contains { ($0["command"] as? String)?.contains("agentide-notify") == true }
            }
            guard alreadyInstalled == false else {
                continue
            }

            entries.append(["hooks": [["type": "command", "command": command]]])
            hooks[event] = entries
        }
        settings["hooks"] = hooks
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys],
        )
        try data.write(to: url, options: .atomic)
    }
}
