import AppIntentsTesting
import Foundation
import Testing

/// The App Intents through the system's own runtime, the way Siri,
/// Shortcuts and Spotlight reach them: out of process, no app code
/// imported. Nothing here starts a session, since a test must not
/// launch an agent; the intents that read are run, the queries are
/// asked, and Start Agent Session is checked to exist and to name
/// its parameters.
struct AgentIDEIntentTests {
    // MARK: Internal

    @Test
    func `what needs me answers without opening the app`() async throws {
        let intent = try #require(definitions.intents["WhatNeedsMeIntent"])
        let result = try await intent.makeIntent().run()
        // A fresh machine has nothing running; a busy one has rows.
        // Either way the value is a list.
        let needing: [Any] = try result.value
        #expect(needing.isEmpty)
    }

    @Test
    func `repositories are found by their own names`() async throws {
        let repositories = try #require(definitions.entities["RepositoryEntity"])
        // What Siri's disambiguation relies on: every suggested
        // repository answers a search for its own name.
        for entity in try await repositories.suggestedEntities() {
            let name: String = try entity.name
            let found = try await repositories.entities(matching: name)
            #expect(try found.contains { try $0.name == name }, Comment(rawValue: name))
        }
    }

    @Test
    func `a worktree search for nonsense finds nothing`() async throws {
        let worktrees = try #require(definitions.entities["WorktreeEntity"])
        let found = try await worktrees.entities(matching: "no-such-branch-" + UUID().uuidString)
        #expect(found.isEmpty)
    }

    @Test
    func `start session is defined with its parameters`() throws {
        let intent = try #require(definitions.intents["StartSessionIntent"])
        for parameter in ["repository", "prompt", "agent"] {
            #expect(intent.parameters[parameter] != nil, Comment(rawValue: parameter))
        }
    }

    @Test
    func `showing an unknown worktree is refused`() async throws {
        let intent = try #require(definitions.intents["ShowWorktreeIntent"])
        // A worktree no query can resolve never reaches perform.
        await #expect(throws: (any Error).self) {
            try await intent.makeIntent(worktree: "/nowhere/" + UUID().uuidString).run()
        }
    }

    // MARK: Private

    private let definitions: IntentDefinitions = .init(bundleIdentifier: "com.mikemcquaid.AgentIDE")
}
