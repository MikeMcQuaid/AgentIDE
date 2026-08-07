/// Builds the sudo, env and sandbox-exec command line that runs a payload as
/// the sandvault sandbox user. This is the single place the launch shape is
/// constructed, so a sandvault change is a one-file fix.
public struct SandvaultLauncher: Sendable {
    // MARK: Lifecycle

    /// Creates a launcher for the given host (GUI) user name.
    public init(hostUser: String) {
        self.hostUser = hostUser
    }

    // MARK: Public

    /// The host user the sandbox identity is derived from.
    public let hostUser: String

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
    /// `/bin/zsh -c`, with the documented environment injected.
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
            "SHELL=/bin/zsh",
            "TERM=xterm-256color",
            "COLORTERM=truecolor",
            "INITIAL_DIR=" + initialDirectory,
            "SHARED_WORKSPACE=" + sharedWorkspace,
            "SV_SESSION_ID=" + sessionID,
            "AGENTIDE_SESSION=" + sessionName,
            "PATH=/usr/bin:/bin:/usr/sbin:/sbin",
            "GIT_CONFIG_COUNT=1",
            "GIT_CONFIG_KEY_0=safe.directory",
            "GIT_CONFIG_VALUE_0=" + sharedWorkspace + "/*",
            "/usr/bin/sandbox-exec", "-f", sandboxProfile,
            "/bin/zsh", "-c", payload,
        ]
    }
}
