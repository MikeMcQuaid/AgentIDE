import AgentIDEData
import Foundation
import TerminalUI

extension DashboardModel {
    /// Reports agent installs Gatekeeper will kill from this app,
    /// with the settings pane that fixes it one click away. Silent
    /// when nothing is quarantined or the privilege is already held.
    func warnAboutGatekeeper() async {
        let files = await service.blockedAgentFiles()
        guard files.isEmpty == false else {
            return
        }

        ErrorLog.shared.report(
            GatekeeperCheck.warning(for: files),
            action: URL(string: GatekeeperCheck.settingsAddress)
                .map { ErrorLog.Action(label: "Open Developer Tools settings", url: $0) },
        )
    }
}
