@testable import AgentIDEData
import Testing

/// Exercises the branch-name normalisation over model answers; the
/// model itself is not exercised, since availability depends on the
/// machine.
struct FoundationModelClientTests {
    @Test
    func `model answers normalise into safe branch names`() {
        #expect(FoundationModelClient.branchName(fromModelAnswer: "Fix Login Crash") == "fix_login_crash")
        #expect(FoundationModelClient.branchName(fromModelAnswer: "`fix_login`.\n") == "fix_login")
        #expect(
            FoundationModelClient.branchName(fromModelAnswer: "fix the crash-on-launch")
                == "fix_the_crash_on_launch",
        )
    }

    @Test
    func `long answers truncate at a word boundary`() throws {
        let truncated = try #require(FoundationModelClient.branchName(
            fromModelAnswer: "summarise every prompt into a very long branch name indeed",
        ))
        #expect(truncated.count <= 40)
        #expect(truncated.hasSuffix("_") == false)
    }

    @Test
    func `unusable answers become nil`() {
        #expect(FoundationModelClient.branchName(fromModelAnswer: "!!!") == nil)
        #expect(FoundationModelClient.branchName(fromModelAnswer: "12 34") == nil)
        #expect(FoundationModelClient.branchName(fromModelAnswer: "") == nil)
    }

    @Test
    func `title answers normalise and unusable ones become nil`() {
        #expect(
            FoundationModelClient.title(fromModelAnswer: "\"Fix the crash\"\nExtra commentary")
                == "Fix the crash",
        )
        #expect(FoundationModelClient.title(fromModelAnswer: "  Plain title  ") == "Plain title")
        #expect(FoundationModelClient.title(fromModelAnswer: "\n\n") == nil)
        let long = String(repeating: "long ", count: 40)
        #expect((FoundationModelClient.title(fromModelAnswer: long)?.count ?? 0) <= 72)
    }

    @Test
    func `a disabled client answers nil`() async {
        let client = FoundationModelClient(isEnabled: false)
        #expect(await client.branchName(for: "fix the crash") == nil)
        #expect(await client.respond(instructions: "echo", to: "hello") == nil)
    }
}
