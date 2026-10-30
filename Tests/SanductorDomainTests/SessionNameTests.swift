import SanductorDomain
import Testing

struct SessionNameTests {
    @Test
    func `makes names in the documented shape`() {
        let name = SessionName.make(repository: "Sanductor", branch: "app_skeleton", agent: .claudeCode)
        #expect(name == "sanductor--sanductor--app-skeleton--claude")
    }

    @Test
    func `slug replaces punctuation and collapses runs`() {
        #expect(SessionName.slug("Fix: v1.2/Thing") == "fix-v1-2-thing")
        #expect(SessionName.slug("--a--b--") == "a-b")
        #expect(SessionName.slug("///") == "unnamed")
    }

    @Test
    func `every made name is recognised as its own`() {
        for agent in AgentKind.allCases {
            let name = SessionName.make(repository: "A B", branch: "Fix: v1.2/Thing", agent: agent)
            #expect(SessionName.isSanductor(name))
        }
    }

    @Test
    func `historical session names still attribute archived conversations`() {
        let name = "agentide--brew--fix-tests--claude"
        #expect(SessionName.isSanductor(name))
        #expect(SessionName.repositorySlug(of: name) == "brew")
        #expect(SessionName.branchSlug(of: name) == "fix-tests")
        #expect(SessionName.isSanductor("agentide--brew--fix-tests--vim") == false)
    }

    @Test
    func `rejects foreign and malformed session names`() {
        #expect(SessionName.isSanductor("boulder-airedale") == false)
        #expect(SessionName.isSanductor("sanductor") == false)
        #expect(SessionName.isSanductor("sanductor--only-prefix") == false)
        #expect(SessionName.isSanductor("sanductor--repo--branch--vim") == false)
        #expect(SessionName.isSanductor("sanductor----branch--claude") == false)
        #expect(SessionName.isSanductor("sanductor--repo--branch--claude--2") == false)
    }
}
