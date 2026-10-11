@testable import AgentIDEData
@testable import DashboardFeature
import Testing

@MainActor
struct FeedbackNoticeTests {
    @Test
    func `completion and attention notify once but restored results stay quiet`() {
        var state = PullRequestAutomation(repositoryPath: "/repo", number: 1, url: "pr")
        state.startLoop()
        let running = state
        state.isAutomatic = false
        state.loopResult = .finished
        #expect(FeedbackNotice.change(from: running, to: state) == .finished)
        #expect(FeedbackNotice.change(from: state, to: state) == nil)
        state.startLoop()
        state.pending = "Push the current fixes before gathering remote feedback"
        #expect(FeedbackNotice.change(from: running, to: state) == .attention)
        #expect(FeedbackNotice.change(from: state, to: state) == nil)
        let waiting = state
        state.stopLoop()
        #expect(FeedbackNotice.change(from: waiting, to: state) == nil)
    }

    @Test
    func `only completion and actionable waits notify`() {
        var state = PullRequestAutomation(repositoryPath: "/repo", number: 1, url: "pr")
        #expect(FeedbackNotice(state) == nil)
        state.startLoop()
        for wait in [
            "Waiting for 2 required CI jobs",
            "Your agent is working on something else. Autofix will wait until it finishes.",
        ] {
            state.pending = wait
            #expect(FeedbackNotice(state) == nil)
        }
        for wait in [
            "Push the current fixes before gathering remote feedback",
            "Waiting for a clean worktree before accepting the fix",
            "Check out feature before autofixing",
        ] {
            state.pending = wait
            #expect(FeedbackNotice(state) == .attention)
        }
        state.stopLoop()
        #expect(FeedbackNotice(state) == nil)
        state.loopResult = .finished
        #expect(FeedbackNotice(state) == .finished)
        #expect(FeedbackNotice.change(from: nil, to: state) == .finished)
        #expect(FeedbackNotice.change(from: state, to: state) == nil)
        state.pushedCommit = "pushed"
        #expect(FeedbackNotice(state) == nil)
        state.pushedCommit = nil
        state.loopResult = .failed
        #expect(FeedbackNotice(state) == .attention)
        state.startLoop()
        state.isAutomatic = false
        state.localRoundLimit = 1
        state.pending = "Push the current fixes before gathering remote feedback"
        state.isAutomatic = true
        #expect(FeedbackNotice(state) == .attention)
    }
}
