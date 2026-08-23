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
    func `done is idle, since the app tracks seen itself`() {
        #expect(AgentActivity(herdrStatus: "done") == .idle)
    }

    @Test
    func `unknown, novel and absent statuses answer nil`() {
        #expect(AgentActivity(herdrStatus: "unknown") == nil)
        #expect(AgentActivity(herdrStatus: "daydreaming") == nil)
        #expect(AgentActivity(herdrStatus: nil) == nil)
    }
}
