#if os(macOS)
    /// Builds the sudo, env and sandbox-exec command line that runs a payload as
    /// the sandvault sandbox user. This is the single place the launch shape is
    /// constructed, so a sandvault change is a one-file fix.
    public struct SandvaultLauncher: SandboxLaunching, Sendable {
        // MARK: Lifecycle

        /// Creates a launcher for the given host (GUI) user name.
        public init(hostUser: String) {
            self.hostUser = hostUser
        }

        // MARK: Public

        /// The host user the sandbox identity is derived from.
        public let hostUser: String

        /// The login shell that runs payloads inside the sandbox.
        public let loginShell = "/bin/zsh"

        /// zsh's disown-and-background, which works without a controlling
        /// terminal (macOS `nohup` does not).
        public let detachSuffix = "&!"

        /// Loads the sandbox user's configure script and zsh startup
        /// files before a long-lived server start.
        public let profileBootstrap =
            "cd ~ && ~/configure; source ~/.zshenv; source ~/.zprofile; source ~/.zshrc; "

        /// Homebrew first: herdr and the agent CLIs live there, and
        /// `env -i` wipes whatever PATH the login shell would build.
        public let sandboxPath =
            "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

        /// The sandbox user, the host user with a `sandvault-` prefix.
        public var sandboxUser: String {
            "sandvault-" + hostUser
        }

        /// The sandbox user's home directory.
        public var sandboxHome: String {
            "/Users/" + sandboxUser
        }

        /// The workspace directory both users read and write.
        public var sharedWorkspace: String {
            "/Users/Shared/sv-" + hostUser
        }

        /// The path of sandvault's generated sandbox-exec profile.
        public var sandboxProfile: String {
            "/var/sandvault/sandbox-" + sandboxUser + ".sb"
        }

        /// The full argv that runs `payload` inside the sandbox through
        /// the login shell, with the documented environment injected.
        public func command(
            payload: String,
            initialDirectory: String,
            sessionID: String,
            sessionName: String,
        ) -> [String] {
            [
                "sudo", "--login", "--set-home", "--user=" + sandboxUser,
                "/usr/bin/env", "-i",
                "HOME=" + sandboxHome,
                "USER=" + sandboxUser,
                "SHELL=" + loginShell,
                "TERM=xterm-256color",
                "COLORTERM=truecolor",
                // Without a UTF-8 locale the multiplexer draws box
                // characters as ASCII, which made agent panes render
                // differently from host shells.
                "LANG=en_US.UTF-8",
                "INITIAL_DIR=" + initialDirectory,
                "SHARED_WORKSPACE=" + sharedWorkspace,
                "SV_SESSION_ID=" + sessionID,
                "AGENTIDE_SESSION=" + sessionName,
                "PATH=" + sandboxPath,
                "GIT_CONFIG_COUNT=1",
                "GIT_CONFIG_KEY_0=safe.directory",
                "GIT_CONFIG_VALUE_0=" + sharedWorkspace + "/*",
                "/usr/bin/sandbox-exec", "-f", sandboxProfile,
                loginShell, "-c", payload,
            ]
        }
    }
#endif
