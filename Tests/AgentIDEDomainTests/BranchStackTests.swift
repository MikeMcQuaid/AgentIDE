import AgentIDEDomain
import Testing

struct BranchStackTests {
    @Test
    func `a stack knows what each branch is built on and what rides on it`() {
        let stack = BranchStack(
            base: "main",
            branches: ["package_manager_caches", "fetch_method", "bottle_linkage"],
            checkedOut: "fetch_method",
        )

        #expect(stack.isStacked)
        #expect(stack.position == 2)
        #expect(stack.parent(of: "package_manager_caches") == "main")
        #expect(stack.parent(of: "fetch_method") == "package_manager_caches")
        #expect(stack.descendants(of: "package_manager_caches") == ["fetch_method", "bottle_linkage"])
        #expect(stack.descendants(of: "bottle_linkage").isEmpty)
        #expect(stack.parent(of: "unknown") == nil)
    }

    @Test
    func `one branch on the default branch is not a stack`() {
        let stack = BranchStack(base: "main", branches: ["fix_the_lexer"], checkedOut: "fix_the_lexer")

        #expect(stack.isStacked == false)
        #expect(stack.position == 1)
        #expect(stack.parent(of: "fix_the_lexer") == "main")
    }
}
