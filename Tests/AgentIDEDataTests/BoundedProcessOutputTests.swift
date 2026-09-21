import AgentIDEData
import Foundation
import Testing

struct BoundedProcessOutputTests {
    @Test(arguments: [false, true])
    func `either output stream is capped while the process runs`(standardError: Bool) async throws {
        let runner: any ProcessRunner = FoundationProcessRunner()
        let result = try await runner.run(
            [
                "/bin/sh", "-c", standardError ? "printf '%s' \"$1\" >&2" : "printf '%s' \"$1\"",
                "bounded-output-test", String(repeating: "x", count: 4_097),
            ],
            workingDirectory: nil,
            environment: [:],
            outputLimit: 4_096,
        )
        #expect(result.outputLimitExceeded)
        #expect(result.succeeded == false)
        #expect(result.standardOutput.utf8.count <= 4_096)
        #expect(result.standardError.utf8.count <= 4_096)
    }

    @Test(arguments: [nil, 262_144] as [Int?])
    func `both streams drain fully through the byte limit`(limit: Int?) async throws {
        let result = try await FoundationProcessRunner().run(
            [
                "/bin/sh", "-c", """
                index=0
                while [ "$index" -lt 64 ]; do
                  printf '%s' "$1"
                  printf '%s' "$2" >&2
                  index=$((index + 1))
                done
                """,
                "bounded-output-test", String(repeating: "x", count: 4_096), String(repeating: "y", count: 4_096),
            ],
            workingDirectory: nil,
            environment: [:],
            outputLimit: limit,
        )
        #expect(result.succeeded)
        #expect(result.outputLimitExceeded == false)
        #expect(result.standardOutput == String(repeating: "x", count: 262_144))
        #expect(result.standardError == String(repeating: "y", count: 262_144))
    }

    @Test(.timeLimit(.minutes(1)))
    func `a process ignoring termination is killed after exceeding its limit`() async throws {
        // Outlive the test deadline so delayed scheduling cannot let the child exit normally.
        let result = try await FoundationProcessRunner().run(
            [
                "/bin/sh", "-c", "trap '' TERM; printf '%s' \"$1\"; exec /bin/sleep 300",
                "bounded-output-test", String(repeating: "x", count: 4_097),
            ],
            workingDirectory: nil,
            environment: [:],
            outputLimit: 4_096,
        )
        #expect(result.outputLimitExceeded)
        #expect(result.status == SIGKILL)
        #expect(result.standardOutput == String(repeating: "x", count: 4_096))
    }

    @Test
    func `a failed launch closes bounded capture`() async {
        await #expect(throws: (any Error).self) {
            try await FoundationProcessRunner().run(
                ["/usr/bin/true"],
                workingDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                environment: [:],
                outputLimit: 4_096,
            )
        }
    }
}
