import Foundation

/// The sandbox user's login keychain, checked the way sandvault's own
/// `configure` checks it and never touched. Since macOS 26.6 a reboot
/// gives that keychain the account's password in place of the empty
/// one sandvault made it with (webcoyote/sandvault#206), after which
/// `configure`'s credential lookup in it raises the "security wants
/// to use the login keychain" dialog at every agent launch and Claude
/// Code's credentials cannot move to sandvault's own keychain. The
/// app says what to run and no more: deleting a keychain is the
/// user's to do.
enum KeychainHealth {
    /// The zsh payload run inside the sandbox, answering on its last
    /// line. Only `unlock-keychain -p ''` is asked of the legacy
    /// keychain, which with a password given never prompts;
    /// `find-generic-password` against a keychain that will not open
    /// is what raises the dialog, so it is asked only of sandvault's
    /// keychain, unlocked first, to see whether the credentials
    /// already moved and the old keychain is merely left behind.
    static let probe = """
    legacy="$HOME/Library/Keychains/login.keychain-db"; \
    own="$HOME/Library/Keychains/sandvault.keychain-db"; \
    [[ -f "$legacy" ]] || { echo no-legacy; exit 0; }; \
    security unlock-keychain -p '' "$legacy" &>/dev/null && { echo legacy-opens; exit 0; }; \
    security unlock-keychain -p '' "$own" &>/dev/null; \
    security find-generic-password -a "$USER" -s 'Claude Code-credentials' "$own" &>/dev/null \
    && { echo migrated; exit 0; }; \
    echo legacy-locked
    """

    /// The steps to run by hand when the probe found the legacy
    /// keychain shut with the credentials still in it; nil when it
    /// opens, is gone or was left behind, and nil too when the probe
    /// did not answer, since a launch that failed says nothing about
    /// a keychain.
    static func advice(from output: String, sandboxUser: String, sandboxHome: String) -> String? {
        let verdict = output.split(separator: "\n").last?.trimmingCharacters(in: .whitespaces)
        guard verdict == "legacy-locked" else {
            return nil
        }

        let keychain = sandboxHome + "/Library/Keychains/login.keychain-db"
        return "The sandbox user's login keychain no longer opens with the password sandvault gave it,"
            + " which macOS 26.6 does to it on a reboot (webcoyote/sandvault#206), so every agent launch"
            + " raises a keychain password dialog and Claude Code's credentials cannot move to sandvault's"
            + " own keychain. To put it right by hand, on the host: run `sv build --rebuild`, remove the"
            + " old keychain with `sudo --user=" + sandboxUser + " /bin/zsh -c 'rm " + keychain + "'`,"
            + " then run `sv claude` and sign in again."
    }
}
