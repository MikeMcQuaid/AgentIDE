extension AgentRunner {
    /// Adapters without a sign-in probe are excluded from setup choices.
    public func authenticationCommand(paths _: WorkspacePaths) -> String? {
        nil
    }

    func authenticationCommand(directories: [String], arguments: [String]) -> String {
        // Braces keep sudo's login shell from expanding these variables before the probe runs.
        "probe_found=false; for binary in "
            + directories.map { ($0 + "/" + kind.rawValue).shellQuoted }.joined(separator: " ")
            + "; do [[ -x \"${binary}\" ]] || continue; probe_found=true; "
            + "if probe_output=$(\"${binary}\" " + arguments.map(\.shellQuoted).joined(separator: " ")
            + " 2>&1); then echo agent=" + kind.rawValue
            + "; else probe_status=$?; printf '%s: sign-in check failed (exit %s). %s\\n' "
            + "\"${binary}\" \"${probe_status}\" \"${probe_output}\" >&2; fi; break; done; "
            + "[[ \"${probe_found}\" == true ]] || echo 'No installed " + kind.rawValue + " binary found.' >&2"
    }
}

extension ClaudeCodeRunner {
    /// Reads only local sign-in state, without invoking sandvault's installing wrapper.
    public func authenticationCommand(paths: WorkspacePaths) -> String? {
        "export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1; " + authenticationCommand(
            directories: [paths.sandboxHome + "/.local/bin"] + Quarantine.homebrewBinaries,
            arguments: ["auth", "status"],
        )
    }

    /// sandvault's Claude wrapper needs the native-install flag even after installation.
    var executable: String {
        "SV_NATIVE_INSTALL=$([[ -x \"$HOME/.local/bin/claude\" ]] && echo true || echo false) claude"
    }
}

public extension CodexRunner {
    /// Matches sandvault's preference for staged or native binaries over Homebrew.
    func authenticationCommand(paths: WorkspacePaths) -> String? {
        authenticationCommand(
            directories: [
                paths.userTemplateDirectory + "/.local/bin", paths.userTemplateDirectory + "/bin",
                paths.sandboxHome + "/.local/bin",
            ] + Quarantine.homebrewBinaries,
            arguments: ["login", "status"],
        )
    }
}
