import Foundation
@testable import SanductorData
import SanductorDomain
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
        #expect(encoded.contains("pushAutomatically") == false)
        #expect(encoded.contains("roundLimit") == false)
        #expect(encoded.contains("roundsStarted") == false)
        #expect(encoded.contains("pushClaimed") == false)
    }

    @Test
    func `missing default fields preserve automation claims`() throws {
        var json = try #require(JSONSerialization.jsonObject(with: Data(Self.legacy.utf8)) as? [String: Any])
        var states = try #require(json["pullRequestAutomation"] as? [String: [String: Any]])
        var state = try #require(states["pr"])
        for key in [
            "isAutomatic", "roundLimit", "roundsStarted", "autofixCopilot", "repeatLocalReview",
            "autofixLocalReviews", "autofixCI", "autofixReviews", "pushAutomatically", "pending", "lastResult",
        ] {
            state[key] = nil
        }
        var attempt = try #require(state["attempt"] as? [String: Any])
        attempt["pushClaimed"] = nil
        state["attempt"] = attempt
        var collection = try #require(state["collection"] as? [String: Any])
        collection["isPending"] = nil
        state["collection"] = collection
        state["resolutions"] = ["thread": ["head": "head", "commentID": "comment"]]
        states["pr"] = state
        json["pullRequestAutomation"] = states
        let metadata = try JSONDecoder().decode(AppMetadata.self, from: JSONSerialization.data(withJSONObject: json))
        let restored = try #require(metadata.pullRequestAutomation["pr"])
        #expect(restored.isAutomatic == false)
        #expect(restored.handledEvents == ["local-ci:run"])
        #expect(restored.attempt?.id == "attempt")
        #expect(restored.collection?.isPending == true)
        #expect(restored.resolutions["thread"]?.requested == false)
        #expect(try JSONDecoder().decode(AppMetadata.self, from: JSONEncoder().encode(metadata)) == metadata)
    }

    @Test
    func `a malformed automation entry preserves other claims and schedules`() throws {
        var metadata = try JSONDecoder().decode(AppMetadata.self, from: Data(Self.legacy.utf8))
        metadata.scheduledPrompts = [ScheduledPrompt(repositoryPath: "/repo")]
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(metadata)) as? [String: Any])
        var states = try #require(json["pullRequestAutomation"] as? [String: Any])
        states["broken"] = ["repositoryPath": "/repo", "number": "invalid"]
        json["pullRequestAutomation"] = states
        let restored = try JSONDecoder().decode(AppMetadata.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(restored.pullRequestAutomation == metadata.pullRequestAutomation)
        #expect(restored.scheduledPrompts == metadata.scheduledPrompts)
        #expect(restored.prompts == metadata.prompts)
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
