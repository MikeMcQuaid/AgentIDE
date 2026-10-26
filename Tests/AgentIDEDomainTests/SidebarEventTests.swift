import AgentIDEDomain
import Foundation
import Testing

struct SidebarEventTests {
    @Test(arguments: ["OPEN", "MERGED", "CLOSED"], [AgentActivity.blocked, .working, .done, .idle])
    func `the newer event wins regardless of state priority`(state: String, activity: AgentActivity) {
        let now = Date()
        let session = AgentSession(
            name: "agent", agent: .codexCLI, status: .running, activity: activity, lastActivityAt: now,
        )
        var pullRequest = PullRequestSummary(
            number: 1,
            title: "Work",
            url: "",
            headBranch: "work",
            mergeable: "",
            reviewDecision: "",
            checks: "",
            state: state,
            stateChangedAt: now.addingTimeInterval(1),
        )
        #expect(session.precedes(pullRequest) == false)
        pullRequest.stateChangedAt = now.addingTimeInterval(-1)
        #expect(session.precedes(pullRequest))
    }

    @Test(arguments: [AgentActivity.blocked, .working, .done, .idle, nil])
    func `equal or missing event times use the previous priority`(activity: AgentActivity?) {
        let now = Date()
        let session = AgentSession(
            name: "agent", agent: .codexCLI, status: .running, activity: activity, lastActivityAt: now,
        )
        var pullRequest = PullRequestSummary(
            number: 1,
            title: "Work",
            url: "",
            headBranch: "work",
            mergeable: "",
            reviewDecision: "",
            checks: "",
            stateChangedAt: now,
        )
        let active = activity.map { [.blocked, .working, .done].contains($0) } ?? false
        #expect(session.precedes(pullRequest) == active)
        pullRequest.stateChangedAt = nil
        #expect(session.precedes(pullRequest) == active)
        #expect(session.precedes(nil))
    }

    @Test
    func `closing time and event times survive edits pushes and caching`() throws {
        let now = Date()
        let merged = PullRequestSummary(
            number: 1,
            title: "Work",
            url: "",
            headBranch: "work",
            mergeable: "",
            reviewDecision: "",
            checks: "",
            state: "MERGED",
            closedAt: now,
        )
        #expect(merged.stateChangedAt == now)
        let edited = merged.retitled("Title", body: "Body").awaitingChecks()
        let decoded = try JSONDecoder().decode(PullRequestSummary.self, from: JSONEncoder().encode(edited))
        #expect(decoded.stateChangedAt == now)
    }
}
