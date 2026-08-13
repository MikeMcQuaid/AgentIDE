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
    func `a disabled client answers nil`() async {
        let client = FoundationModelClient(isEnabled: false)
        #expect(await client.branchName(for: "fix the crash") == nil)
        #expect(await client.respond(instructions: "echo", to: "hello") == nil)
    }
}
