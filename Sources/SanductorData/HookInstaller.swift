import Foundation

/// Installs Sanductor's hook script and Claude Code hook entries into
/// the sandvault user template, alongside any existing third-party
/// notifier hooks rather than replacing them.
struct HookInstaller {
    // MARK: Lifecycle

    /// Creates an installer for a workspace.
    init(paths: WorkspacePaths) {
        self.paths = paths
    }

    // MARK: Internal

    /// The events the hook reports, covering completion, permission
    /// requests and lifecycle for the dashboard.
    static let events = [
        "UserPromptSubmit", "Stop", "StopFailure", "PostToolUse",
        "PostToolUseFailure", "PermissionRequest", "SessionStart", "SessionEnd",
    ]

    /// Ensures the sanductor directories, the hook script and the
    /// settings template entries all exist. Idempotent.
    func ensureInstalled() throws {
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
        paths.userTemplateDirectory + "/.claude/sanductor-notify.sh"
    }

    private var settingsPath: String {
        paths.userTemplateDirectory + "/.claude/settings.json"
    }

    private var scriptContent: String {
        """
        #!/bin/sh
        if [ "${0##*/}" = agentide-notify.sh ]; then
          printf 'Warning: agentide-notify.sh is deprecated; use sanductor-notify.sh instead.\n' >&2
        fi
        if [ -z "${SANDUCTOR_SESSION+x}" ] && [ -n "${AGENTIDE_SESSION+x}" ]; then
          printf 'Warning: AGENTIDE_SESSION is deprecated; use SANDUCTOR_SESSION instead.\n' >&2
        fi
        session="${SANDUCTOR_SESSION-${AGENTIDE_SESSION-${SV_SESSION_ID:-}}}"
        [ -n "$session" ] || exit 0
        directory="${SHARED_WORKSPACE:-\(paths.sharedWorkspace)}/sanductor/events"
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
        let legacy = paths.userTemplateDirectory + "/.claude/agentide-notify.sh"
        try? FileManager.default.removeItem(atPath: legacy)
        try FileManager.default.createSymbolicLink(atPath: legacy, withDestinationPath: "sanductor-notify.sh")
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
                return nested.contains { hook in
                    let installed = hook["command"] as? String ?? ""
                    return installed.contains("sanductor-notify") || installed.contains("agentide-notify")
                }
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
