import AgentIDEDomain
import AgentIDERemote

/// Session creation is never replayed after an ambiguous disconnect.
extension MobileModel {
    func create(repository: String, agent: AgentKind, model: String, effort: String, prompt: String) async -> Bool {
        guard let remote else {
            return false
        }

        return await create(on: remote) {
            try await remote.create(repository: repository, agent: agent, model: model, effort: effort, prompt: prompt)
        }
    }

    func create(on remote: RemoteHerdr, start: () async throws -> String) async -> Bool {
        guard self.remote === remote, isConnected, isCreating == false else {
            return false
        }

        isCreating = true
        defer { isCreating = false }
        progress.begin("Creating a worktree and starting the agent")
        do {
            let paneID = try await start()
            try? await read(remote, includingPreferences: true)
            if self.remote === remote, isConnected {
                selection = sessions.first { $0.id == paneID }
            }
            return true
        } catch {
            self.error = configuration.errorMessage(error)
                + " Check the session list before retrying; the session may have started."
            return false
        }
    }
}
