import AgentIDEDomain
import Testing

/// Naming a checkout by GitHub's `owner/name`, the only identity the
/// repository finder trusts: a fork and its upstream share the bare
/// name.
struct RepositoryTests {
    @Test
    func `a checkout is named by owner and name, ignoring case`() {
        let fork = Repository(name: "Example", path: "/r/Example", fullName: "octocat/Example")
        #expect(fork.isNamed("octocat/Example"))
        #expect(fork.isNamed("OctoCat/example"))
        #expect(fork.isNamed("example-org/Example") == false)
        #expect(Repository(name: "Example", path: "/r/Example").isNamed("octocat/Example") == false)
    }
}
