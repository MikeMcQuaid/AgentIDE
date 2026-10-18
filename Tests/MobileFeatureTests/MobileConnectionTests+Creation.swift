import AgentIDERemote
import Foundation
@testable import MobileFeature
import Testing

extension MobileConnectionTests {
    @Test(arguments: [false, true])
    func `confirmed creation succeeds despite refresh failure or disconnect`(disconnect: Bool) async {
        let connected = UserDefaults.standard.object(forKey: "sshConnected")
        defer { UserDefaults.standard.set(connected, forKey: "sshConnected") }
        let configuration = SSHConfiguration()
        let model = MobileModel(configuration: configuration)
        let remote = RemoteHerdr(configuration: configuration)
        model.remote = remote
        model.didConnect()
        var starts = 0
        let created = await model.create(on: remote) {
            starts += 1
            if disconnect {
                model.disconnect()
            }
            return "created-pane"
        }
        #expect(created)
        #expect(starts == 1)
        #expect(model.isCreating == false)
        #expect(model.selection == nil)
        #expect(model.error == nil)
        model.disconnect()
    }

    @Test
    func `ambiguous creation failure warns without replaying the request`() async {
        let connected = UserDefaults.standard.object(forKey: "sshConnected")
        defer { UserDefaults.standard.set(connected, forKey: "sshConnected") }
        let configuration = SSHConfiguration()
        let model = MobileModel(configuration: configuration)
        let remote = RemoteHerdr(configuration: configuration)
        model.remote = remote
        model.didConnect()
        var starts = 0
        let created = await model.create(on: remote) {
            starts += 1
            throw RemoteError("Connection lost")
        }
        #expect(created == false)
        #expect(starts == 1)
        #expect(model.isCreating == false)
        #expect(model.error?.contains("may have started") == true)
        model.disconnect()
    }
}
