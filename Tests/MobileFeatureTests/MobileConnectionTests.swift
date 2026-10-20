import AgentIDERemote
import Foundation
@testable import MobileFeature
import Testing

@Suite(.serialized)
struct MobileConnectionTests {
    @Test(arguments: [false, true])
    func `app switches retain only established connections`(connected: Bool) {
        let saved = UserDefaults.standard.object(forKey: "sshConnected")
        let configurationData = UserDefaults.standard.data(forKey: "sshConfiguration")
        defer {
            UserDefaults.standard.set(saved, forKey: "sshConnected")
            UserDefaults.standard.set(configurationData, forKey: "sshConfiguration")
        }
        var configuration = SSHConfiguration()
        configuration.host = "127.0.0.1"
        configuration.username = "sandvault-test"
        let model = MobileModel(configuration: configuration)
        model.reconnect()
        let remote = RemoteHerdr(configuration: configuration)
        model.remote = remote
        if connected {
            model.didConnect()
            model.selection = MobileSession(
                id: "pane", name: "session", repository: "repo", branch: "main", agent: .codexCLI, activity: nil,
            )
        }
        let generation = model.connectionGeneration
        let selection = model.selection
        for _ in 0 ..< 3 {
            model.suspend()
            model.activate()
            #expect(model.isConnected == connected)
            #expect(model.isConnecting == false)
            #expect((model.remote === remote) == connected)
            #expect(model.connectionGeneration == generation)
            #expect(model.selection == selection)
        }
        if connected {
            model.terminalDisconnected()
            #expect(model.isConnecting)
            #expect(model.isConnected == false)
            #expect(model.selection == selection)
        }
        let reopened = MobileModel(configuration: configuration)
        reopened.activate()
        #expect(reopened.isConnecting == connected)
        reopened.disconnect()
        model.disconnect()
    }

    @Test(arguments: [false, true])
    func `launch reconnects only when the previous visit was connected`(wasConnected: Bool) {
        let saved = UserDefaults.standard.object(forKey: "sshConnected")
        let configurationData = UserDefaults.standard.data(forKey: "sshConfiguration")
        defer {
            UserDefaults.standard.set(saved, forKey: "sshConnected")
            UserDefaults.standard.set(configurationData, forKey: "sshConfiguration")
        }
        UserDefaults.standard.set(wasConnected, forKey: "sshConnected")
        var configuration = SSHConfiguration()
        configuration.host = "127.0.0.1"
        configuration.username = "sandvault-test"
        let model = MobileModel(configuration: configuration)
        model.activate()
        #expect(model.isConnecting == wasConnected)
        #expect(model.isDisconnected == !wasConnected)
        model.disconnect()
        let reopened = MobileModel(configuration: configuration)
        reopened.activate()
        #expect(reopened.isDisconnected)
        #expect(reopened.isConnecting == false)
        reopened.disconnect()
    }

    @Test
    func `a manual disconnect survives foregrounding until Connect is chosen`() async {
        let saved = UserDefaults.standard.data(forKey: "sshConfiguration")
        let connected = UserDefaults.standard.object(forKey: "sshConnected")
        defer {
            UserDefaults.standard.set(saved, forKey: "sshConfiguration")
            UserDefaults.standard.set(connected, forKey: "sshConnected")
        }
        var configuration = SSHConfiguration()
        configuration.host = "127.0.0.1"
        configuration.username = "sandvault-test"
        let model = MobileModel(configuration: configuration)
        model.reconnect()
        #expect(model.isConnecting)
        model.error = "Previous error"
        model.pendingHostKey = "pending"
        model.disconnect()
        model.suspend()
        model.activate()
        #expect(model.isDisconnected)
        #expect(model.isConnecting == false)
        #expect(model.isConnected == false)
        #expect(model.error == nil)
        #expect(model.pendingHostKey == nil)
        #expect(model.remote == nil)
        model.reconnect()
        #expect(model.isDisconnected == false)
        #expect(model.isConnecting)
        model.disconnect()
        for _ in 0 ..< 3 {
            await Task.yield()
        }
        #expect(model.isConnecting == false)
        #expect(model.remote == nil)
    }
}
