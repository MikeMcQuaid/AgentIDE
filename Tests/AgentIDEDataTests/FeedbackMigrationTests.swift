@testable import AgentIDEData
import Foundation
import Testing

struct FeedbackMigrationTests {
    // MARK: Internal

    @Test
    func `retired local CI preserves claims and comments without enabling more work`() throws {
        let metadata = try JSONDecoder().decode(AppMetadata.self, from: Data(Self.legacy.utf8))
        let state = try #require(metadata.pullRequestAutomation["pr"])
        let attempt = try #require(state.attempt)
        #expect(state.selectedSources.isEmpty)
        #expect(state.autofixCodeRabbit == false)
        #expect(state.botRequests == nil)
        #expect(state.hasLocalSources == false)
        #expect(state.allows(attempt.sources) == false)
        #expect(state.handledEvents == ["local-ci:run"])
        #expect(state.resolutions["thread"]?.commentID == "comment")
        #expect(metadata.prompts["session"] == "Keep this prompt")
        let encoded = try #require(String(data: JSONEncoder().encode(metadata), encoding: .utf8))
        #expect(encoded.contains("autofixLocalCI") == false)
        #expect(encoded.contains("localCICommand") == false)
        #expect(encoded.contains("ciOutput") == false)
    }

    // MARK: Private

    private static let legacy = """
    {
      "prompts": {"session": "Keep this prompt"},
      "repositoryFeedbackDefaults": {"/repo": {"localCICommand": "script/test"}},
      "pullRequestAutomation": {"pr": {
        "repositoryPath": "/repo", "number": 1, "url": "pr",
        "isAutomatic": true, "roundLimit": 1, "roundsStarted": 1,
        "autofixLocalCI": true, "autofixCopilot": false, "localCICommand": "script/test",
        "repeatLocalReview": false, "autofixLocalReviews": false,
        "autofixCI": false, "autofixReviews": false, "pushAutomatically": true,
        "pending": "", "lastResult": "", "handledEvents": ["local-ci:run"],
        "resolutions": {"thread": {"head": "head", "commentID": "comment", "requested": false}},
        "collection": {
          "id": "run", "revision": "head", "configuration": "ci", "isPending": false,
          "ciFailed": true, "ciOutput": "Tests failed"
        },
        "attempt": {
          "id": "attempt", "sources": ["localCI"], "head": "head", "remoteHead": "head",
          "localThreadIDs": [], "branch": "feature", "worktreePath": "/worktree",
          "sessionName": "session", "paneID": "pane", "threads": {}, "pushClaimed": false
        }
      }}
    }
    """
}
