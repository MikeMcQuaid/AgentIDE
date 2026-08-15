import AgentIDEDomain
import Testing

struct SessionNameTests {
    @Test
    func `makes names in the documented shape`() {
        let name = SessionName.make(repository: "AgentIDE", branch: "app_skeleton", agent: .claudeCode)
        #expect(name == "agentide--agentide--app-skeleton--claude")
    }

    @Test
    func `slug replaces everything tmux forbids and collapses runs`() {
        #expect(SessionName.slug("Fix: v1.2/Thing") == "fix-v1-2-thing")
        #expect(SessionName.slug("--a--b--") == "a-b")
        #expect(SessionName.slug("///") == "unnamed")
    }

    @Test
    func `every made name is recognised as its own`() {
        for agent in AgentKind.allCases {
            let name = SessionName.make(repository: "A B", branch: "Fix: v1.2/Thing", agent: agent)
            #expect(SessionName.isAgentIDE(name))
        }
    }

    @Test
    func `rejects foreign and malformed session names`() {
        #expect(SessionName.isAgentIDE("boulder-airedale") == false)
        #expect(SessionName.isAgentIDE("agentide") == false)
        #expect(SessionName.isAgentIDE("agentide--only-prefix") == false)
        #expect(SessionName.isAgentIDE("agentide--repo--branch--vim") == false)
        #expect(SessionName.isAgentIDE("agentide----branch--claude") == false)
        #expect(SessionName.isAgentIDE("agentide--repo--branch--claude--2") == false)
    }
}
