import AgentIDEDomain
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
}
