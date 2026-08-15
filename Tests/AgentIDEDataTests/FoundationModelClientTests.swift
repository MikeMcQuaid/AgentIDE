@testable import AgentIDEData
import Testing

/// Exercises the branch-name normalisation over model answers; the
/// model itself is not exercised, since availability depends on the
/// machine.
struct FoundationModelClientTests {
    @Test
    func `description answers capitalise and collapse doubled dashes`() {
        // Models echo commit bodies that are already dash lists and
        // prefix another dash, and sometimes lowercase the title.
        let doubled = """
        attach tmux control mode clients

        - - Fix protocol decoding at the byte level
        -  - Keep hidden panes from swallowing input
        - Show failures inline
          continuation lines and --flags stay untouched
        """
        let parsed = FoundationModelClient.pullRequestDescription(fromModelAnswer: doubled)
        #expect(parsed?.title == "Attach tmux control mode clients")
        #expect(parsed?.body == """
        - Fix protocol decoding at the byte level
        - Keep hidden panes from swallowing input
        - Show failures inline
          continuation lines and --flags stay untouched
        """)
        #expect(FoundationModelClient.pullRequestDescription(fromModelAnswer: "  \n\n") == nil)
    }

    @Test
    func `commit digests carry every subject and bodies while they fit`() {
        let commits = [
            "First change\n\nWhy the first change happened.",
            "Second change",
            "Third change\n\nA very long explanation of the third change's why.",
        ]
        let full = FoundationModelClient.commitDigest(commits, limit: 1_000)
        #expect(full.contains("Subjects:\nFirst change\nSecond change\nThird change"))
        #expect(full.contains("Why the first change happened."))
        #expect(full.contains("A very long explanation"))
        // Body-less commits add nothing to the details section.
        #expect(full.contains("Second change\n\n") == false)

        // A tight budget keeps every subject and drops later bodies
        // rather than truncating the subject list.
        let tight = FoundationModelClient.commitDigest(commits, limit: 120)
        #expect(tight.contains("Subjects:\nFirst change\nSecond change\nThird change"))
        #expect(tight.contains("Why the first change happened."))
        #expect(tight.contains("A very long explanation") == false)
    }

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
