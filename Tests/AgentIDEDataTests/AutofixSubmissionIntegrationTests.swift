@testable import AgentIDEData
import Foundation
import Testing

struct AutofixSubmissionIntegrationTests {
    @Test
    func `autofix sends Enter outside bracketed paste to submit a terminal prompt`() async throws {
        let (client, home) = try TestSupport.makeHerdrClient()
        let directory = try TestSupport.temporaryDirectory("autofix-submit")
        defer { TestSupport.stopServerSync(configHome: home) }
        // A named foreground agent which records exactly what reaches the terminal.
        try """
        #include <unistd.h>
        int main(void) {
            char byte;
            while (read(0, &byte, 1) > 0) {
                if (write(1, &byte, 1) != 1) return 1;
            }
            return 0;
        }
        """.write(toFile: directory + "/receiver.c", atomically: true, encoding: .utf8)
        try await TestSupport.run(["clang", "receiver.c", "-o", "codex"], in: directory)
        try await client.newSession(
            name: "reviewer",
            directory: directory,
            command: "stty raw -echo; printf '\\033[?2004h'; ./codex >submitted",
        )
        #expect(await TestSupport.poll { FileManager.default.fileExists(atPath: directory + "/submitted") })
        let pane = try #require(try await client.panes().first)
        try await client.herdr([
            "pane", "report-agent", pane.paneID, "--source", "test", "--agent", "codex", "--state", "idle",
        ])
        try await client.sendAutofix("Fix the supplied findings", sessionName: "reviewer", paneID: pane.paneID)
        #expect(await TestSupport.poll {
            (try? String(contentsOfFile: directory + "/submitted", encoding: .utf8))?.hasSuffix("\r") == true
        })
        let received = try String(contentsOfFile: directory + "/submitted", encoding: .utf8)
        #expect(received == "\u{1B}[200~Fix the supplied findings\u{1B}[201~\r")
    }
}
