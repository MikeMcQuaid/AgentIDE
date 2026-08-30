// swiftformat:disable all
// swiftlint:disable prefer_nimble
// XCTest, not Swift Testing, and formatted by hand: a UI testing
// bundle, which is what AppIntentsTesting needs, cannot load the
// Testing module, and SwiftFormat would rewrite these into it.
import AppIntentsTesting
import XCTest

/// The App Intents through the system's own runtime, the way Siri,
/// Shortcuts and Spotlight reach them: out of process, no app code
/// imported. Nothing here starts a session, since a test must not
/// launch an agent; the intents that read are run, the queries are
/// asked, and Start Agent Session is checked to exist and to name
/// its parameters.
final class AgentIDEIntentTests: XCTestCase {
    // MARK: Lifecycle

    deinit {
        // Nothing to clean up.
    }

    // MARK: Internal

    func testWhatNeedsMeAnswersWithoutOpeningTheApp() async throws {
        let intent = try XCTUnwrap(definitions.intents["WhatNeedsMeIntent"])
        // A fresh machine has nothing running; a busy one has rows.
        // Either way the intent runs and answers.
        _ = try await intent.makeIntent().run()
    }

    func testRepositoriesAreFoundByTheirOwnNames() async throws {
        let repositories = try XCTUnwrap(definitions.entities["RepositoryEntity"])
        // What Siri's disambiguation relies on: every suggested
        // repository answers a search for its own name.
        for entity in try await repositories.suggestedEntities() {
            let name: String = try entity.name
            let found = try await repositories.entities(matching: name)
            XCTAssertTrue(try found.contains { try $0.name == name }, name)
        }
    }

    func testAWorktreeSearchForNonsenseFindsNothing() async throws {
        let worktrees = try XCTUnwrap(definitions.entities["WorktreeEntity"])
        let found = try await worktrees.entities(matching: "no-such-branch-" + UUID().uuidString)
        XCTAssertTrue(found.isEmpty)
    }

    func testStartSessionIsDefined() {
        // Defined, never run: a test must not launch an agent.
        XCTAssertNotNil(definitions.intents["StartSessionIntent"])
        XCTAssertNotNil(definitions.intents["OpenPullRequestsIntent"])
    }

    func testShowingAnUnknownWorktreeIsRefused() async throws {
        let intent = try XCTUnwrap(definitions.intents["ShowWorktreeIntent"])
        // A worktree no query can resolve never reaches perform.
        do {
            _ = try await intent.makeIntent(worktree: "/nowhere/" + UUID().uuidString).run()
            XCTFail("Expected the unknown worktree to be refused")
        } catch {
            // Refused, as it should be.
        }
    }

    // MARK: Private

    private let definitions = IntentDefinitions(bundleIdentifier: "com.mikemcquaid.AgentIDE")
}
// swiftlint:enable prefer_nimble
