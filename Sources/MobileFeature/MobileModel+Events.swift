import AgentIDERemote

extension MobileModel {
    func subscribe(
        open: ([String]) async throws -> SSHCommand,
        receive: (SSHCommand) async throws -> Void,
    ) async throws {
        repeat {
            resubscribe = false
            let events = try await open(eventPaneIDs)
            defer { events.close() }
            try Task.checkCancellation()
            eventChannel = events
            // A refresh may have changed the pane list while opening.
            guard resubscribe == false else {
                continue
            }

            do {
                try await receive(events)
            } catch {
                if resubscribe == false {
                    throw error
                }
            }
            try Task.checkCancellation()
        } while resubscribe
        throw RemoteError("The SSH connection ended.")
    }
}
