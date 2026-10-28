import AppKit
@testable import DashboardFeature
import Foundation
import SanductorData
import SanductorDomain
import SwiftUI
import Testing

/// A failed launch stays on its own row; split from the suite's
/// file for length, and serialised with it, since both write the
/// form's draft to the shared defaults.
extension SessionNavigationTests {
    @Test(arguments: [true, false])
    func `a failed placeholder retries into the form or dismisses back to its checkout`(retry: Bool) {
        let fixture = Fixture()
        defer { fixture.close() }
        let main = fixture.model.groups[0].items[0]
        let placeholder = Worktree(
            repositoryName: fixture.repository.name,
            repositoryPath: fixture.repository.path,
            branch: "issue-12",
            path: fixture.repository.path + DashboardModel.placeholderMarker + "issue-12",
        )
        let item = WorktreeItem(
            worktree: placeholder,
            session: nil,
            isDirty: false,
            aheadOfUpstream: nil,
            hasUnread: false,
        )
        fixture.model.groups[0].items.append(item)
        fixture.model.selection = item
        let draft = LaunchDraft(
            text: "Fix it",
            source: .issue,
            agent: .claudeCode,
            options: AgentLaunchOptions(),
            number: 12,
            base: "part_one",
        )
        fixture.model.launchFailures[placeholder.path] = LaunchFailure(message: "worktree add failed", draft: draft)
        #expect(fixture.model.launchFailure(for: item)?.message == "worktree add failed")

        if retry {
            fixture.model.retryLaunch(for: placeholder)
        } else {
            fixture.model.dismissLaunchFailure(for: placeholder)
        }

        #expect(fixture.model.launchFailures.isEmpty)
        #expect(fixture.model.groups[0].items.map(\.worktree.path) == [main.worktree.path])
        #expect(fixture.model.selection?.id == main.id)
        #expect(fixture.model.showsNewSession == retry)
        #expect(fixture.model.newSessionBase == (retry ? "part_one" : nil))
        let expected = LaunchRetry(repositoryPath: fixture.repository.path, worktreePath: nil, draft: draft)
        #expect(fixture.model.launchRetry == (retry ? expected : nil))
    }

    @Test(arguments: [true, false])
    func `only the form a failed launch came from takes back its issue and context`(isOwnForm: Bool) async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let restore = Fixture.overriding([
            AgentSessionForm.promptKey: "",
            "agentKind": "claude",
            "agentModel": "sonnet",
            "agentEffort": "high",
        ])
        defer { restore() }
        let worktree = fixture.model.groups[0].items[0].worktree
        fixture.model.discoveredModels[.codexCLI] = ["test-model"]
        await fixture.model.launchAgent(
            fromIssue: 12,
            in: worktree,
            context: "Fix it",
            agent: .codexCLI,
            options: AgentLaunchOptions(model: "test-model", effort: "low"),
        )
        let failure = try #require(fixture.model.launchFailures[worktree.path])
        var submitted: AgentSessionForm.Submission?
        let form = AgentSessionForm(
            model: fixture.model,
            repository: fixture.repository,
            worktreePath: isOwnForm ? worktree.path : fixture.root,
            submitTitle: "Start agent",
            submitHelp: "Start",
        ) { submission in submitted = submission }
        let host = NSHostingView(rootView: AnyView(form))
        let window = Fixture.window(hosting: host)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(100))

        fixture.model.retryLaunch(for: worktree)
        try await Task.sleep(for: .milliseconds(100))

        #expect(fixture.model.launchRetry?.draft == (isOwnForm ? nil : failure.draft))
        // Submitting proves the form took the issue, not just the text.
        if isOwnForm {
            try fixture.typeAndSubmit(in: host, windowNumber: window.windowNumber)
            for _ in 0 ..< 50 where submitted == nil {
                try await Task.sleep(for: .milliseconds(10))
            }
            let submission = try #require(submitted)
            #expect(submission.source == .issue)
            #expect(submission.numbers == [12])
            #expect(submission.context == "Fix it prompt")
            #expect(submission.agent == .codexCLI)
            #expect(submission.options == AgentLaunchOptions(model: "test-model", effort: "low"))
        }
    }
}
