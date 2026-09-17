import Foundation
import Synchronization

// MARK: - KeychainCheck

/// Whether the sandbox user's keychain has been probed this run: the
/// answer changes only through a reboot or the steps it names, and
/// each probe is a sudo login shell.
final class KeychainCheck: Sendable {
    // MARK: Lifecycle

    deinit {
        // Nothing to clean up.
    }

    // MARK: Internal

    let asked: Mutex<Bool> = .init(false)
}

// MARK: - The sandbox keychain

public extension SessionService {
    /// What to run by hand when the sandbox user's login keychain no
    /// longer opens (`KeychainHealth`); nil when it does, when it is
    /// gone or left behind, and after the first answer of a run.
    func sandboxKeychainAdvice() async -> String? {
        let first = keychainCheck.asked.withLock { asked in
            defer { asked = true }
            return asked == false
        }
        guard first else {
            return nil
        }

        await progress("Checking that the sandbox user's login keychain still opens")
        let argv = launcher.command(
            payload: KeychainHealth.probe,
            initialDirectory: launcher.sharedWorkspace,
            sessionID: UUID().uuidString,
            sessionName: "agentide-keychain",
        )
        let result = try? await processes.run(argv, workingDirectory: nil, environment: [:])
        return KeychainHealth.advice(
            from: result?.standardOutput ?? "",
            sandboxUser: launcher.sandboxUser,
            sandboxHome: launcher.sandboxHome,
        )
    }
}
