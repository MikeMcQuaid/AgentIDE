import AgentIDEDomain
import Testing

struct GitWorktreeStatusTests {
    @Test
    func `branch spelling and upstream counts are preserved`() {
        let status = GitWorktreeStatus(porcelain:
            "# branch.head Feature/login_fix\0# branch.upstream origin/main\0# branch.ab +12 -3\0? new file\0")
        #expect(status.branch == "Feature/login_fix")
        #expect(status.aheadOfUpstream == 12)
        #expect(status.behindUpstream == 3)
        #expect(status.isDirty)
        #expect(status.summary == "↑12 ↓3 ±")
    }

    @Test(arguments: ["1 .M", "2 R.", "u UU", "?"])
    func `changed filenames cannot masquerade as branch headers`(kind: String) {
        let status = GitWorktreeStatus(porcelain:
            "# branch.head main\0" + kind + " name\n# branch.head wrong\0"
                + (kind == "2 R." ? "# branch.head old-name\0" : ""))
        #expect(status.isDirty)
        #expect(status.branch == "main")
    }

    @Test
    func `a clean detached head has neither a branch nor invented counts`() {
        let status = GitWorktreeStatus(porcelain: "# branch.head (detached)\0")
        #expect(status.branch == nil)
        #expect(status.isDirty == false)
        #expect(status.aheadOfUpstream == nil)
        #expect(status.behindUpstream == nil)
        #expect(status.summary.isEmpty)
    }
}
