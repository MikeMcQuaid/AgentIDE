/// Reading a pane's output back from herdr, which holds the
/// scrollback the local buffer does not. Split from the sessions
/// file for length.
extension HerdrClient {
    /// The last lines of a pane's output as text, with the hard
    /// wraps the terminal's width forced removed, so a long answer
    /// copies whole where a selection could only ever hold the
    /// rendered screen. Nil when herdr cannot answer.
    func readPane(paneID: String, lines: Int) async -> String? {
        let result = try? await herdr(
            ["pane", "read", paneID, "--source", "recent-unwrapped", "--lines", String(lines), "--format", "text"],
            allowFailure: true,
        )
        guard let result, result.succeeded else {
            return nil
        }

        return result.standardOutput
    }
}
