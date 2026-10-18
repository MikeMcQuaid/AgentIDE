import AgentIDERemote
import Darwin
import Foundation
import NIOCore
import Testing

struct SSHErrorMessageTests {
    @Test(arguments: [
        (EPERM, "permission"), (EACCES, "permission"), (ECONNREFUSED, "Remote Login"),
        (ETIMEDOUT, "timed out"), (ENETUNREACH, "network"), (EHOSTUNREACH, "network"),
        (ECONNRESET, "closed"),
    ])
    func `socket failures explain the cause and destination`(code: Int32, guidance: String) {
        var configuration = SSHConfiguration()
        configuration.host = " \tmac.example.com\n"
        let message = configuration.errorMessage(IOError(errnoCode: code, reason: "connect"))
        #expect(message.contains("mac.example.com on port 22"))
        #expect(message.contains(guidance))
        #expect(message.contains("NIOCore") == false)
    }

    @Test
    func `timeouts and actionable SSH errors retain useful guidance`() {
        var configuration = SSHConfiguration()
        configuration.host = "mac.example.com"
        #expect(configuration.errorMessage(ChannelError.connectTimeout(.seconds(15))).contains("timed out"))
        let message = "Install this phone's public key for the sandbox user."
        #expect(configuration.errorMessage(RemoteError(message)) == message)
        #expect(configuration.errorMessage(SSHHostKeyError.changed).contains("host key has changed"))
    }
}
