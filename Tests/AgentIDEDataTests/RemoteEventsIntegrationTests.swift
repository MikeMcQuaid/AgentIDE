@testable import AgentIDEData
@testable import AgentIDERemote
import Foundation
import Testing

struct RemoteEventsIntegrationTests {
    @Test
    func `the phone subscription receives agent status changes`() async throws {
        let (herdr, home) = try TestSupport.makeHerdrClient()
        defer { TestSupport.stopServerSync(configHome: home) }
        try await herdr.newSession(name: "agentide--repo--phone--claude", directory: home, command: "sleep 20")
        let pane = try #require(try await herdr.panes().first)
        let subscription = try #require(String(
            data: RemoteHerdr.eventSubscription(paneIDs: [pane.paneID]), encoding: .utf8,
        ))
        let script = """
        import json, socket, sys
        stream = socket.socket(socket.AF_UNIX)
        stream.settimeout(5)
        stream.connect(sys.argv[1])
        stream.sendall((sys.argv[2] + '\\n').encode())
        lines = stream.makefile('r')
        assert json.loads(lines.readline())['result']['type'] == 'subscription_started'
        report = socket.socket(socket.AF_UNIX)
        report.settimeout(5)
        report.connect(sys.argv[1])
        report.sendall((json.dumps({'id': 'test', 'method': 'pane.report_agent', 'params': {
            'pane_id': sys.argv[3], 'agent': 'claude', 'source': 'phone-test', 'state': 'blocked'
        }}) + '\\n').encode())
        assert json.loads(report.makefile('r').readline())['result']['type'] == 'ok'
        while True:
            event = json.loads(lines.readline())
            if event.get('event') == 'pane.agent_status_changed':
                print(event['data']['agent_status'])
                break
        """
        let result = try await FoundationProcessRunner().run(
            ["/usr/bin/python3", "-c", script, home + "/herdr/herdr.sock", subscription, pane.paneID],
            workingDirectory: nil,
            environment: [:],
        )
        #expect(result.succeeded, "\(result.standardError)")
        #expect(result.standardOutput == "blocked\n")
    }
}
