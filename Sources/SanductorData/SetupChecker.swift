import Foundation

/// Checks prerequisites without launching servers, installing tools or signing in.
public struct SetupChecker: Sendable {
    // MARK: Lifecycle

    /// Reuses the app's clients and sandbox boundary.
    public init(
        service: SessionService,
        isInsideSandbox: Bool = WorkspacePaths.isInsideSandbox,
        requiresSignedCommits: Bool = AppSettings.requiresSignedCommits,
    ) {
        self.service = service
        self.isInsideSandbox = isInsideSandbox
        self.requiresSignedCommits = requiresSignedCommits
    }

    // MARK: Public

    /// File work stays off the main actor; subprocesses finish asynchronously.
    @concurrent
    public func check(verifyOnline: Bool) async -> SetupResult {
        guard isInsideSandbox == false else {
            return SetupResult(issues: [
                SetupIssue(
                    step: .tools,
                    title: "Open Sanductor as your normal macOS user",
                    explanation: "GitHub credentials belong to your account, outside sandvault.",
                    commands: "open /Applications/Sanductor.app",
                    alternative: "Run this command in Terminal outside the sandbox.",
                ),
            ], agents: [])
        }

        let missing = await missingTools()
        guard missing.isEmpty else {
            return SetupResult(issues: missing, agents: [])
        }

        for runner in service.runners {
            _ = Quarantine.clear(for: runner.kind, binaryDirectories: agentBinaryDirectories)
        }
        async let git = gitConfiguration()
        async let github = githubAccess(verifyOnline: verifyOnline)
        let sandbox = await sandboxAccess()
        let identity = await git
        return await SetupResult(
            issues: identity.issues + github + sandbox.issues,
            agents: sandbox.agents,
            signingConfigured: identity.signingConfigured,
        )
    }

    // MARK: Internal

    var agentBinaryDirectories: [String] = Quarantine.homebrewBinaries

    let service: SessionService
    let requiresSignedCommits: Bool

    // MARK: Private

    private let isInsideSandbox: Bool

    private static func toolsIssue(missing: String) -> SetupIssue {
        SetupIssue(
            step: .tools,
            title: "Install required tools",
            explanation: "Missing or unavailable: " + missing
                + ". If `brew` is missing, follow the installation instructions at [brew.sh](https://brew.sh). "
                + "Then run these commands in Terminal as your normal macOS user.",
            commands: "brew install git gh herdr ripgrep sandvault",
            alternative: "",
        )
    }

    private func missingTools() async -> [SetupIssue] {
        do {
            let result = try await service.processes.run(
                [
                    "/bin/zsh", "-fc", """
                    for tool in brew git gh herdr rg sv; do command -v "$tool" &>/dev/null || echo "$tool"; done
                    if [[ "$(command -v git)" == /usr/bin/git ]] && ! /usr/bin/xcode-select -p &>/dev/null; then
                        echo git
                    fi
                    """,
                ],
                workingDirectory: nil,
                environment: [:],
            )
            guard result.succeeded else {
                return [Self.toolsIssue(missing: "Could not check installed commands")]
            }

            return result.standardOutput.isEmpty ? [] : [
                Self.toolsIssue(missing: result.standardOutput.split(separator: "\n").joined(separator: ", ")),
            ]
        } catch {
            return [Self.toolsIssue(missing: error.localizedDescription)]
        }
    }

    private func githubAccess(verifyOnline: Bool) async -> [SetupIssue] {
        do {
            guard await service.github.hasStoredAuthentication() else {
                throw SessionServiceError("GitHub CLI has no stored authentication")
            }

            if verifyOnline {
                try await service.github.gh(["auth", "status", "--hostname", "github.com"], in: nil)
                try await service.github.gh(["api", "--hostname", "github.com", "user", "--jq", ".login"], in: nil)
            }
            return []
        } catch {
            return [
                SetupIssue(
                    step: .github,
                    title: "Connect your GitHub account",
                    explanation: "GitHub CLI needs a sign-in in your normal macOS account. "
                        + (verifyOnline ? "First-time setup also needs internet access." : "Sign in and recheck."),
                    commands: "gh auth login --hostname github.com --git-protocol https --web",
                    alternative: "Choose Yes if asked to authenticate Git with your GitHub credentials. "
                        + "Authorise organisation SSO if your repositories require it. "
                        + "Keep GitHub credentials outside sandvault.",
                ),
            ]
        }
    }
}
