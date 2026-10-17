import AgentIDEDomain
import Foundation

extension SetupChecker {
    func sandboxAccess() async -> SetupResult {
        guard FileManager.default.isWritableFile(atPath: service.paths.sharedWorkspace) else {
            return SetupResult(issues: [Self.sandboxRepair], agents: [])
        }

        if let failure = prepareWorkspace() {
            return SetupResult(issues: [failure], agents: [])
        }
        let result = try? await service.processes.run(
            service.launcher.command(
                payload: sandboxProbe,
                initialDirectory: service.paths.sharedWorkspace,
                sessionID: UUID().uuidString,
                sessionName: "agentide-setup",
            ),
            workingDirectory: nil,
            environment: [:],
        )
        let lines = (result?.standardOutput ?? "").split(separator: "\n")
        guard result?.succeeded == true, lines.contains("sandbox-ready") else {
            return SetupResult(issues: [Self.sandboxRepair], agents: [])
        }

        let agents = service.runners.map(\.kind).filter { lines.contains("agent=" + $0.rawValue) }
        var issues = [SetupIssue]()
        if lines.contains("legacy-locked"),
           let advice = KeychainHealth.advice(
               from: "legacy-locked", sandboxUser: service.launcher.sandboxUser, sandboxHome: service.paths.sandboxHome,
           )
        {
            issues.append(SetupIssue(
                step: .agent, title: "Repair the sandbox keychain", explanation: advice, commands: "", alternative: "",
            ))
        }
        if agents.isEmpty, issues.isEmpty {
            issues.append(SetupIssue(
                step: .agent,
                title: "Set up an agent inside sandvault",
                explanation: "Choose one agent to install and sign in inside sandvault.",
                commands: "sv claude\n\nsv codex",
                alternative: "Complete the agent's sign-in, quit it and recheck here.\n\n"
                    + (result?.standardError.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""),
            ))
        }
        return SetupResult(issues: issues, agents: agents)
    }

    private static let sandboxRepair: SetupIssue = .init(
        step: .sandbox,
        title: "Set up sandvault",
        explanation: "AgentIDE needs the sandbox account, its profile and passwordless access "
            + "to a writable shared workspace. Run setup in Terminal, where you can authorise it.",
        commands: "sv build",
        alternative: "If an existing setup is broken, use `sv build --rebuild` instead.",
    )

    private var sandboxProbe: String {
        "cd \"${HOME}\" || exit 1; "
            + "export TMPDIR=$(/usr/bin/getconf DARWIN_USER_TEMP_DIR) || exit 1; "
            + "[[ -x \"${HOME}/configure\" ]] || exit 1; "
            + [service.paths.repositoriesDirectory, service.paths.worktreesDirectory, service.paths.promptsDirectory]
            .map { "[[ -w " + $0.shellQuoted + " ]] || exit 1; " }
            .joined()
            + "command -v herdr &>/dev/null || exit 1; "
            + "keychain=$(" + KeychainHealth.probe + "); echo \"${keychain}\"; "
            + "[[ \"${keychain}\" == legacy-locked ]] && { echo sandbox-ready; exit 0; }; "
            + service.runners
            .compactMap { $0.authenticationCommand(paths: service.paths) }
            .map { "(" + $0 + ") & " }
            .joined()
            + "wait; echo sandbox-ready"
    }

    private func prepareWorkspace() -> SetupIssue? {
        do {
            for directory in [service.paths.repositoriesDirectory, service.paths.worktreesDirectory] {
                try service.requireSandboxWorkspace(directory)
                try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            }
            try HookInstaller(paths: service.paths).ensureInstalled()
            return nil
        } catch {
            return SetupIssue(
                step: .sandbox,
                title: "Make the workspace writable",
                explanation: error.localizedDescription,
                commands: "sv build --rebuild",
                alternative: "Repository and worktree locations must be inside `" + service.paths.sharedWorkspace
                    + "`. To reset custom locations, run `defaults delete "
                    + (Bundle.main.bundleIdentifier ?? "com.mikemcquaid.AgentIDE") + " "
                    + AppSettings.repositoriesDirectoryKey + "` and the same command for `"
                    + AppSettings.worktreesDirectoryKey + "`, then reopen AgentIDE.",
            )
        }
    }
}
