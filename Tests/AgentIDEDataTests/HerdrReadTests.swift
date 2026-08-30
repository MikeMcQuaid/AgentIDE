@testable import AgentIDEData
import Foundation
import Testing

/// A whole-output copy asks herdr for recent, unwrapped text.
struct HerdrReadTests {
    @Test
    func `reading a pane asks for recent unwrapped text`() async {
        let runner = RecordingRunner()
        let herdr = HerdrClient(
            runner: runner,
            launcher: SandvaultLauncher(hostUser: "test"),
            isInsideSandbox: true,
            configHome: "/tmp/herdr-read-test",
        )
        _ = await herdr.readPane(paneID: "w1:p1", lines: 5_000)
        let command = runner.commands.last ?? []
        let pairs = zip(command, command.dropFirst()).map { [$0, $1] }
        #expect(command.contains("w1:p1"))
        #expect(pairs.contains(["--source", "recent-unwrapped"]))
        #expect(pairs.contains(["--lines", "5000"]))
        #expect(pairs.contains(["--format", "text"]))
    }
}
