import SanductorRemote

extension MobileModel {
    func terminal(paneID: String) async throws -> SSHCommand {
        guard let remote, isConnected else {
            throw RemoteError("Reconnect before opening a terminal.")
        }

        return try await remote.terminal(paneID: paneID)
    }
}
