import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

struct SessionActivityTests {
    @Test(arguments: [AgentKind.claudeCode, .codexCLI])
    func `old completed turns stay idle when viewed and return on new input`(agent: AgentKind) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let path = world.repository.path
        let name = SessionName.make(repository: "repo", branch: "main", agent: agent)
        let directory = agent == .codexCLI
            ? world.paths.sandboxHome + "/.codex/sessions"
            : try #require(PromptCaptureRunner().transcriptDirectory(
                workingDirectory: path, sandboxHome: world.paths.sandboxHome,
            ))
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let transcript = directory + "/conversation.jsonl"
        let content = """
        {"type":"session_meta","payload":{"cwd":"\(path)","id":"conversation"}}
        {"type":"user","message":{"content":[{"type":"text","text":"input"}]}}
        """
        try content.write(toFile: transcript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-86_401)], ofItemAtPath: transcript,
        )
        world.service.store.update { metadata in
            metadata.sessionsByWorktree[path] = name
        }
        world.service.lastPanes.remember([
            HerdrPane(
                sessionName: name,
                paneID: "pane",
                isFinished: false,
                activity: .done,
                foregroundCommand: nil,
                currentPath: path,
            ),
        ])
        var service = world.service
        service.selectedWorktreePath = { path }
        let initial = await service.overview(readingPanes: false)
        #expect(initial.groups.first?.items.first?.session?.sidebarActivity == .idle)

        let viewed = await service.overview(scope: .only([]), kept: initial.groups, readingPanes: false)
        #expect(viewed.groups.first?.items.first?.session?.sidebarActivity == .idle)
        #expect(viewed.groups.first?.items.first?.session?.activity == .done)

        // An input hook updates even when Git and the pane listing are reused.
        try FileManager.default.createDirectory(atPath: world.paths.eventsDirectory, withIntermediateDirectories: true)
        try "{\"hook_event_name\":\"UserPromptSubmit\"}\n".write(
            toFile: world.paths.eventsDirectory + "/" + name + ".jsonl", atomically: true, encoding: .utf8,
        )
        let updated = await service.overview(scope: .only([]), kept: viewed.groups, readingPanes: false)
        #expect(updated.groups.first?.items.first?.session?.sidebarActivity == .done)
    }
}
