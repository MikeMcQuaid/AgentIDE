import AgentIDEDomain
import Testing

/// Which repositories a sidebar reading asks git about.
struct GitReadScopeTests {
    @Test
    func `all includes everything and only includes its own`() {
        #expect(GitReadScope.all.includes("/repo"))
        let some = GitReadScope.only(["/repo"])
        #expect(some.includes("/repo"))
        #expect(some.includes("/other") == false)
    }
}
