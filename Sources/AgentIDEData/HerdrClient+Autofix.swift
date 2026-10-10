import AgentIDEDomain

extension HerdrClient {
    /// Pins the pane and checks the live agent immediately before submitting.
    func sendAutofix(_ text: String, sessionName: String, paneID: String) async throws {
        guard let row = try await snapshotRows().first(where: { $0.paneID == paneID }),
              row.sessionName == sessionName, row.agent != nil,
              row.activity == .done || row.activity == .idle
        else {
            throw SessionServiceError("The autofix target is no longer a ready, running agent")
        }

        let process = await foreground(paneID: paneID)
        guard process.isShell == false, process.command != nil else {
            throw SessionServiceError("The autofix target's running agent could not be verified")
        }

        try await herdr(["agent", "prompt", paneID, text])
    }
}
