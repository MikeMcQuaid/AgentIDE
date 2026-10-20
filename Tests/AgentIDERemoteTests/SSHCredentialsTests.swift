@testable import AgentIDERemote
import Crypto
import Foundation
import Security
import Testing

struct SSHCredentialsTests {
    @Test
    func `a concurrent identity creator uses the key already stored`() throws {
        let winner = Curve25519.Signing.PrivateKey().rawRepresentation
        var reads = 0
        let key = try SSHCredentials.privateKey(
            read: {
                reads += 1
                return reads == 1 ? nil : winner
            },
            insert: { _ in errSecDuplicateItem },
        )
        #expect(key.rawRepresentation == winner)
    }

    @Test
    func `an existing identity is never replaced`() throws {
        let stored = Curve25519.Signing.PrivateKey().rawRepresentation
        let key = try SSHCredentials.privateKey(read: { stored }, insert: { _ in
            Issue.record("Attempted to replace the existing identity")
            return errSecSuccess
        })
        #expect(key.rawRepresentation == stored)
    }

    @Test
    func `a newly created identity matches the stored key`() throws {
        var stored: Data?
        let key = try SSHCredentials.privateKey(read: { nil }, insert: { data in
            stored = data
            return errSecSuccess
        })
        #expect(key.rawRepresentation == stored)
    }

    @Test(arguments: [errSecDuplicateItem, errSecAuthFailed])
    func `an unavailable identity never falls back to an unsaved key`(status: OSStatus) {
        #expect(throws: RemoteError.self) {
            try SSHCredentials.privateKey(read: { nil }, insert: { _ in status })
        }
    }
}
