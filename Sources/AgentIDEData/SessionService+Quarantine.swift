import AgentIDEDomain
import Foundation

extension SessionService {
    /// Clears Gatekeeper's quarantine from the agent's install before
    /// a launch, narrating what it cleared; see `Quarantine`.
    func clearQuarantine(for agent: AgentKind) async {
        let cleared = Quarantine.clear(for: agent).map { URL(filePath: $0).lastPathComponent }
        guard cleared.isEmpty == false else {
            return
        }

        await progress("Cleared Gatekeeper quarantine from `" + cleared.joined(separator: "`, `") + "`")
    }
}
