import AgentIDEDomain
import Foundation
import Testing

/// The mapping from herdr's status strings to the app's activity.
struct AgentActivityTests {
    @Test
    func `herdr statuses map to activities`() {
        #expect(AgentActivity(herdrStatus: "working") == .working)
        #expect(AgentActivity(herdrStatus: "blocked") == .blocked)
        #expect(AgentActivity(herdrStatus: "idle") == .idle)
    }

    @Test
    func `done is its own state: an answer is waiting, idle owes nothing`() {
        #expect(AgentActivity(herdrStatus: "done") == .done)
        #expect(AgentActivity(herdrStatus: "done") != AgentActivity(herdrStatus: "idle"))
    }

    @Test
    func `unknown, novel and absent statuses answer nil`() {
        #expect(AgentActivity(herdrStatus: "unknown") == nil)
        #expect(AgentActivity(herdrStatus: "daydreaming") == nil)
        #expect(AgentActivity(herdrStatus: nil) == nil)
    }

    @Test(arguments: [86_399.0, 86_400.0, 86_401.0])
    func `completed turns become idle only after twenty four hours`(age: TimeInterval) {
        let now = Date()
        let session = AgentSession(
            name: "agent",
            agent: .codexCLI,
            status: .running,
            activity: .done,
            lastActivityAt: now.addingTimeInterval(-age),
            now: now,
        )
        #expect(session.sidebarActivity == (age > 86_400 ? .idle : .done))
        #expect(session.activity == .done)
    }

    @Test(arguments: [AgentActivity.working, .blocked, .idle, nil])
    func `other agent states never expire`(activity: AgentActivity?) {
        let session = AgentSession(
            name: "agent",
            agent: .codexCLI,
            status: .running,
            activity: activity,
            lastActivityAt: .distantPast,
        )
        #expect(session.sidebarActivity == activity)
    }

    @Test
    func `completed turns with no known time stay done`() {
        let session = AgentSession(name: "agent", agent: .codexCLI, status: .running, activity: .done)
        #expect(session.sidebarActivity == .done)
    }
}
