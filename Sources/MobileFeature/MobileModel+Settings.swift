import Foundation
import SanductorRemote

extension MobileModel {
    /// Restores the destination and loads the phone’s public key.
    public convenience init() {
        self.init(configuration: UserDefaults.standard
            .data(forKey: "sshConfiguration")
            .flatMap { try? JSONDecoder().decode(SSHConfiguration.self, from: $0) } ?? SSHConfiguration())
        do {
            publicKey = try SSHCredentials.publicKey()
        } catch {
            self.error = configuration.errorMessage(error)
        }
    }

    func trustHost(_ key: String) {
        do {
            try SSHCredentials.trust(key, for: configuration.hostIdentity)
            pendingHostKey = nil
            reconnect()
        } catch {
            self.error = configuration.errorMessage(error)
        }
    }

    func forgetHost() {
        deactivate()
        do {
            try SSHCredentials.forgetHost(configuration.hostIdentity)
            error = "The saved host key was removed. Reconnect to verify the new key."
        } catch {
            self.error = configuration.errorMessage(error)
        }
    }
}
