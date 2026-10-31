@testable import DashboardFeature
@testable import SanductorData
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
        state.pending = "Integrate the current PR head before autofixing"
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
            "Waiting for 2 CI jobs",
            "Your agent is working on something else. Autofix will wait until it finishes.",
        ] {
            state.pending = wait
            #expect(FeedbackNotice(state) == nil)
        }
        for wait in [
            "Integrate the current PR head before autofixing",
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
        state.loopResult = .failed
        #expect(FeedbackNotice(state) == .attention)
        state.startLoop()
        state.isAutomatic = false
        state.localRoundLimit = 1
        state.pending = "Integrate the current PR head before autofixing"
        state.isAutomatic = true
        #expect(FeedbackNotice(state) == .attention)
    }
}
