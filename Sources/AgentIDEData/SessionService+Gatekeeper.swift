import Foundation

public extension SessionService {
    /// The agents' installed files Gatekeeper will kill from this
    /// app; see `GatekeeperCheck`.
    func blockedAgentFiles() async -> [String] {
        await GatekeeperCheck(runner: processes).blockedFiles()
    }
}
