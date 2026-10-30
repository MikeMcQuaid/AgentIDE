import Foundation

public extension LegacyMigration {
    /// Whether guest-owned state still needs its one-time migration.
    static func isSandboxMigrationNeeded(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: sandboxCompletedKey) == false
    }

    /// Guest-owned state migrates with the guest's existing permissions.
    @concurrent
    static func prepareSandbox(
        paths: WorkspacePaths,
        runner: any ProcessRunner = FoundationProcessRunner(),
        defaults: UserDefaults = .standard,
    ) async throws {
        guard isSandboxMigrationNeeded(defaults: defaults) else {
            return
        }

        if FileManager.default.fileExists(atPath: paths.sharedWorkspace + "/agentide")
            || FileManager.default.fileExists(atPath: paths.sandboxHome + "/.config/herdr/sessions/agentide")
            || FileManager.default.fileExists(atPath: paths.sandboxHome + "/.config/herdr/sessions/agentide-dev")
        {
            try HookInstaller(paths: paths).ensureInstalled()
            let result = try await runner.run(
                SandvaultLauncher(hostUser: paths.hostUser).command(
                    payload: sandboxScript,
                    initialDirectory: paths.sharedWorkspace,
                    sessionID: UUID().uuidString,
                    sessionName: "sanductor-migration",
                ),
                workingDirectory: nil,
                environment: [:],
            )
            guard result.succeeded else {
                throw CommandError(command: "Migrate agent sessions", result: result)
            }
        }
        defaults.set(true, forKey: sandboxCompletedKey)
    }

    // MARK: Internal

    internal static let sandboxScript = #"""
    set -eu;
    cd "${HOME}";
    ./configure;
    for legacy in agentide agentide-dev; do
      current="${legacy/agentide/sanductor}";
      sessions="${XDG_CONFIG_HOME:-${HOME}/.config}/herdr/sessions";
      if [[ -d "${sessions}/${legacy}" && ! -e "${sessions}/${current}" && ! -L "${sessions}/${current}" ]]; then
        ln -s "${legacy}" "${sessions}/${current}";
      fi;
    done;
    if [[ -d "${SHARED_WORKSPACE}/agentide" ]]; then
      destination="${SHARED_WORKSPACE}/sanductor";
      mkdir -p "${destination}";
      /usr/bin/rsync -rlt --ignore-existing --omit-dir-times "${SHARED_WORKSPACE}/agentide/" "${destination}/";
    fi
    """#

    // MARK: Private

    private static let sandboxCompletedKey = "agentideSandboxMigrationComplete"
}
