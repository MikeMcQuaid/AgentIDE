@testable import AgentIDERemote
import Foundation
import Testing

struct RemoteLinesTests {
    @Test
    func `packet boundaries may split Unicode and several records`() throws {
        let bytes = Array("雪\nnext\nlast".utf8)
        var parser = RemoteLines()
        #expect(try parser.append(Data(bytes.prefix(2))).isEmpty)
        #expect(try parser.append(Data(bytes.dropFirst(2))) == ["雪", "next"])
        #expect(try parser.append(Data("\n".utf8)) == ["last"])
    }

    @Test
    func `remote arguments are quoted and session paths cannot escape`() {
        #expect(SSHConfiguration.quote("a'b;$(exit)") == "'a'\\''b;$(exit)'")
        var configuration = SSHConfiguration()
        configuration.host = "mac"
        configuration.username = "sandvault-test"
        #expect(configuration.isValid)
        configuration.session = "../other"
        #expect(configuration.isValid == false)
    }
}
