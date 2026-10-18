import AgentIDERemote
import Foundation
import Testing

struct SSHConfigurationTests {
    @Test(arguments: [" \tMac.Example.com\r\n", "\u{00A0}Mac.Example.com\u{00A0}"])
    func `pasted and saved hosts share the same host-key pin`(host: String) throws {
        var configuration = SSHConfiguration()
        configuration.host = host
        configuration.port = 2_222
        configuration.username = "sandvault-test"
        #expect(configuration.isValid)
        #expect(configuration.hostIdentity == "mac.example.com:2222")
        let restored = try JSONDecoder().decode(SSHConfiguration.self, from: JSONEncoder().encode(configuration))
        #expect(restored.hostIdentity == "mac.example.com:2222")
    }

    @Test(arguments: ["", " \r\n\t"])
    func `whitespace alone is not a host`(host: String) {
        var configuration = SSHConfiguration()
        configuration.host = host
        configuration.username = "sandvault-test"
        #expect(configuration.isValid == false)
    }

    @Test(arguments: ["192.0.2.1", "2001:db8::1", "mac.example.com"])
    func `SSH accepts IP addresses and hostnames`(host: String) {
        var configuration = SSHConfiguration()
        configuration.host = host
        configuration.username = "sandvault-test"
        #expect(configuration.isValid)
        #expect(configuration.session == "agentide")
    }

    @Test(arguments: ["test", "sv-test", "sandvault-", "sandvault- ", "sandvault-test\n", "sandvault-test@mac"])
    func `SSH requires a complete sandbox account name`(username: String) {
        var configuration = SSHConfiguration()
        configuration.host = "mac.example.com"
        configuration.username = username
        #expect(configuration.isValid == false)
    }
}
